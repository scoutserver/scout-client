require "net/https"
require "uri"
require "yaml"
require "timeout"
require "stringio"
require "zlib"
require "socket"
require "base64"

module Scout
  class ServerBase
    include Scout::HTTP

    # A new class for plugin Timeout errors.
    class PluginTimeoutError < RuntimeError; end
    # A new class for API Timeout errors.
    class APITimeoutError < RuntimeError; end

    # Headers passed up with all API requests.
    HTTP_HEADERS = { "Client-Version"  => Scout::VERSION,
                     "Accept-Encoding" => "gzip" }


    private

    def urlify(url_name, options = Hash.new)
      return unless @server
      options.merge!(:client_version => Scout::VERSION)
      uri = URI.join(@server,
               "/clients/CLIENT_KEY/#{url_name}.scout".
                   gsub(/\bCLIENT_KEY\b/, @client_key).
                   gsub(/\b[A-Z_]+\b/) { |k| options[k.downcase.to_sym] || k })
      uri.query = ["roles=#{@roles}","hostname=#{URI.encode(@hostname)}","env=#{URI.encode(@environment)}","tty=#{$stdin.tty? ? 'y' : 'n'}"].join('&')
      uri
    end

    def post(url, error, body, headers = Hash.new, &response_handler)
      return unless url
      request(url, response_handler, error) do |connection|
        post = Net::HTTP::Post.new(url.path +
                                       (url.query ? ('?' + url.query) : ''),
                                   HTTP_HEADERS.merge(headers))
        post.body = body
        connection.request(post)
      end
    end

    def get(url, error, headers = Hash.new, &response_handler)
      return unless url
      request(url, response_handler, error) do |connection|
        connection.get(url.path + (url.query ? ('?' + url.query) : ''),
                       HTTP_HEADERS.merge(headers))
      end
    end

    def request(uri, response_handler, error, &connector)
      response = nil
      Timeout.timeout(5 * 60, APITimeoutError) do
        http = build_http(uri)

        response = no_warnings { http.start(&connector) }
      end
      case response
        when Net::HTTPSuccess, Net::HTTPNotModified
          response_handler[response] unless response_handler.nil?
        else
          error = "Server says: #{response['x-scout-msg']}" if response['x-scout-msg']
          fatal error
          raise SystemExit.new(error)
      end
    rescue Timeout::Error
      fatal "Request timed out."
      exit
    rescue Exception
      raise if $!.is_a? SystemExit
      fatal "An HTTP error occurred:  #{$!.message}"
      exit
    end

    def no_warnings
      old_verbose = $VERBOSE
      $VERBOSE = false
      yield
    ensure
      $VERBOSE = old_verbose
    end

    # Forward Logger methods to an active instance, when there is one.
    def method_missing(meth, *args, &block)
      if (Logger::SEV_LABEL - %w[ANY]).include? meth.to_s.upcase
        @logger.send(meth, *args, &block) unless @logger.nil?
      else
        super
      end
    end
  end
end
