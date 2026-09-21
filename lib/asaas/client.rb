# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Asaas
  class Client
    RETRY_STATUSES     = [429, 500, 502, 503, 504].freeze
    IDEMPOTENT_METHODS = %i[post put patch].freeze
    MAX_LOG_BODY_BYTES = 200
    SENSITIVE_LOG_KEYS = %w[
      accesskey
      accesssecret
      accesstoken
      apikey
      apisecret
      authkey
      authenticationtoken
      authorization
      authtoken
      bearertoken
      clientsecret
      creditcard
      creditcardholderinfo
      creditcardtoken
      idtoken
      password
      privatekey
      refreshtoken
      cardnumber
      creditcardnumber
      ccv
      cvv
      number
      remoteip
      secret
      secretkey
      sessiontoken
      token
      webhooktoken
    ].freeze
    HTTP_METHODS = {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete
    }.freeze

    def initialize(config = Asaas.config, api_key: nil)
      @config  = config
      @api_key = api_key || config.api_key
    end

    # @param method  [:get, :post, :put, :patch, :delete]
    # @param path    [String]
    # @param params  [Hash]
    # @param headers [Hash]
    # @return [Hash]
    def request(method, path, params: {}, headers: {}, retryable: true, timeout: nil, idempotency_key: nil) # rubocop:disable Metrics/ParameterLists
      validate_config!

      uri = build_uri(path, method == :get ? params : {})
      body = method == :get ? {} : params
      request_headers = build_headers(headers, idempotency_key_for(method, idempotency_key))
      request_headers["Idempotency-Key"] = idempotency_key if explicit_idempotency_key?(method, idempotency_key)
      operation = -> { perform(method, uri, body, request_headers, timeout: timeout) }

      retryable ? with_retries(&operation) : operation.call
    end

    private

    def validate_config!
      return unless @api_key.nil? || @api_key.empty?

      raise ConfigurationError, "Asaas.api_key is not set. Call Asaas.configure { |c| c.api_key = '...' }"
    end

    def build_uri(path, query_params = {})
      uri = URI.parse("#{@config.base_url}#{path}")
      uri.query = URI.encode_www_form(flatten_params(query_params)) if query_params.any?
      uri
    end

    def build_headers(extra = {}, idempotency_key = nil)
      headers = {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "access_token" => @api_key,
        "User-Agent" => "AsaasRuby/#{Asaas::VERSION}"
      }
      headers["Idempotency-Key"] = idempotency_key if idempotency_key
      headers.merge(extra)
    end

    def idempotency_key_for(method, explicit_key)
      return unless IDEMPOTENT_METHODS.include?(method)
      return SecureRandom.uuid if explicit_key.nil?
      return explicit_key if explicit_key.is_a?(String) && !explicit_key.strip.empty?

      raise ArgumentError, "idempotency_key must be a non-blank String"
    end

    def explicit_idempotency_key?(method, key)
      IDEMPOTENT_METHODS.include?(method) && !key.nil?
    end

    def perform(method, uri, body, headers, timeout: nil)
      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.read_timeout = timeout || @config.timeout
      http.open_timeout = timeout || @config.timeout

      req = build_request(method, uri, headers, body)

      log_request(method, uri, body)

      res = begin
        http.request(req)
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT,
             Net::OpenTimeout, Net::ReadTimeout, SocketError => e
        raise ConnectionError, "Network error: #{e.message}"
      end

      log_response(res)
      parse_response(res)
    end

    def build_request(method, uri, headers, body)
      req = HTTP_METHODS.fetch(method).new(uri.request_uri, headers)
      encode_body(req, body) if body.any?
      req
    end

    def encode_body(req, body)
      if multipart?(body)
        req.delete("Content-Type")
        req.set_form(to_multipart_parts(body), "multipart/form-data")
      else
        req.body = JSON.generate(body)
      end
    end

    def multipart?(params)
      params.values.any? { |v| v.respond_to?(:read) }
    end

    def to_multipart_parts(params)
      params.map do |k, v|
        if v.respond_to?(:read)
          filename = v.respond_to?(:path) ? File.basename(v.path) : k.to_s
          [k.to_s, v, { filename: filename }]
        else
          [k.to_s, v.to_s]
        end
      end
    end

    def parse_response(res)
      status     = res.code.to_i
      request_id = res["X-Request-Id"]
      body       = parse_body(res.body)

      raise Asaas.error_for_status(status, body, request_id) unless (200..299).cover?(status)

      body
    end

    def parse_body(raw)
      return {} if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def with_retries
      attempts = 0
      begin
        yield
      rescue RateLimitError, ServerError, ConnectionError => e
        attempts += 1
        if attempts <= @config.max_retries && retryable?(e)
          sleep(@config.retry_delay * (2**(attempts - 1)))
          retry
        end
        raise
      end
    end

    def retryable?(error)
      case error
      in ConnectionError | RateLimitError then true
      in ServerError if RETRY_STATUSES.include?(error.http_status) then true
      else false
      end
    end

    def flatten_params(params, prefix = nil)
      params.each_with_object({}) do |(k, v), result|
        key = prefix ? "#{prefix}[#{k}]" : k.to_s
        case v
        when Hash  then result.merge!(flatten_params(v, key))
        when Array then result[key] = v.join(",")
        else            result[key] = v
        end
      end
    end

    def log_request(method, uri, body)
      return unless @config.logger

      body_log = if body.none?
                   ""
                 elsif multipart?(body)
                   " [multipart/form-data: #{body.keys.join(", ")}]"
                 else
                   " #{sanitize(body).to_json}"
                 end

      @config.logger.debug("[Asaas] --> #{method.upcase} #{uri}#{body_log}")
    end

    def log_response(res)
      return unless @config.logger

      parsed_body = JSON.parse(res.body.to_s)
      @config.logger.debug("[Asaas] <-- #{res.code} #{bounded_log_json(parsed_body)}")
    rescue JSON::ParserError
      @config.logger.debug("[Asaas] <-- #{res.code} #{res.body.to_s.bytesize} bytes")
    end

    def bounded_log_json(value)
      sanitized_json = JSON.generate(sanitize(value))
      return sanitized_json if sanitized_json.bytesize <= MAX_LOG_BODY_BYTES

      JSON.generate("_truncated" => true, "_bytes" => sanitized_json.bytesize)
    end

    def sanitize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), sanitized|
          sanitized[key] = sensitive_key?(key) ? "[FILTERED]" : sanitize(nested_value)
        end
      when Array
        value.map { |nested_value| sanitize(nested_value) }
      else
        value
      end
    end

    def sensitive_key?(key)
      normalized_key = key.to_s.downcase.gsub(/[^a-z0-9]/, "")
      SENSITIVE_LOG_KEYS.include?(normalized_key)
    end
  end
end
