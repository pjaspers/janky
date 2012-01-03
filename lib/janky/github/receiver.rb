module Janky
  module GitHub
    # Rack app handling GitHub Post-Receive [1] requests.
    #
    # The JSON payload is parsed into a GitHub::Payload. We then find the
    # associated Repository record based on the Payload's repository git URL
    # and create the associated records: Branch, Commit and Build.
    #
    # Finally, we trigger a new Jenkins build.
    #
    # [1]: http://help.github.com/post-receive-hooks/
    class Receiver
      def initialize(secret)
        @secret = secret
      end

      def call(env)
        dup.call!(env)
      end

      def call!(env)
        @request = Rack::Request.new(env)

        if !valid_signature?
          return Rack::Response.new("Invalid signature", 403).finish
        end

        if !payload.head_commit
          return Rack::Response.new("Ignored", 400).finish
        end

        result = BuildRequest.handle(
          payload.uri,
          payload.branch,
          payload.head_commit,
          payload.compare,
          @request.POST["room"]
        )

        Rack::Response.new("OK: #{result}", 201).finish
      end

      def valid_signature?
        warn "REQUEST ENV:"
        # warn @request.env.inspect
        data
        # Temporarily avoiding signature validation.
        return true

        digest    = OpenSSL::Digest::Digest.new("sha1")
        signature = @request.env["HTTP_X_HUB_SIGNATURE"].split("=").last

        signature == OpenSSL::HMAC.hexdigest(digest, @secret, data)
      end

      def payload
        warn "##################################################\n\n\n"
        warn data
        warn "\n\n\n##################################################"
        @payload ||= GitHub::Payload.parse(data)
      end

      def data
        @data ||= data!
      end

      def data!
        # if @request.content_type != "application/json"
        #   return Rack::Response.new("Invalid Content-Type", 400).finish
        # end

        body = ""
        @request.body.each { |chunk| body << chunk }
        body

        # If legacy web hooks are used we're getting a url encoded json
        # body back. This will trip up the parsing. So fixing it here
        if body.match /^payload/
          body = CGI::unescape(body.gsub(/^payload=/, ""))
        end
      end
    end
  end
end
