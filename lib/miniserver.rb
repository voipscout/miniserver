require 'rack'
require 'celluloid/io'
require 'http_tools'

module MiniServer
  class Server
    include Celluloid::IO

    NAME = 'MiniServer'
    VERSION = '0.1'

    def initialize(host, port, app)
      @server = TCPServer.new(host, port)
      @server.to_io.do_not_reverse_lookup = true
      @server.to_io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      @app = app
      run!
    end

    def self.run(app, options = {})
      server = new(options[:host] || '0.0.0.0', options[:port] || 8080, app)
      puts ">> Using Rack adapter"
      puts ">> #{NAME} v#{VERSION}"
      puts ">> Listening on #{options[:host] || '0.0.0.0'}:#{options[:port] || 8080}, CTRL+C to stop"
      sleep
    rescue SystemExit, Interrupt
      server.terminate
    end

    protected

    def run
      loop { handle! @server.accept }
    rescue FiberError
      nil
    end

    def handle(socket)
      parser = HTTPTools::Parser.new
      parser << socket.readpartial(4096) until parser.finished?
      env = parser.env

      env.update 'REMOTE_ADDR'       => socket.peeraddr.last,
                 'SERVER_SOFTWARE'   => NAME,
                 'GATEWAY_INTERFACE' => 'CGI/1.2',
                 'SERVER_PROTOCOL'   => 'HTTP/1.1'

      status, headers, body = @app.call(env)

      respond(socket, status, headers, body)
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, Errno::EINVAL, Errno::EBADF => e
      STDERR.puts "#{Time.now}: Socket error: #{e.inspect}"
    rescue Object => e
      STDERR.puts "#{Time.now}: Internal error: #{e.message}"
    ensure
      socket.close
    end

    def respond(socket, status, headers, rbody)
      body = StringIO.new
      rbody.each { |part|
        body.write(part)
      }
      body.rewind

      headers['Content-Length'] = body.length if body.length and status.to_i != 304
      headers['Date'] = Time.now.httpdate

      socket.write("HTTP/1.1 %d %s\r\nConnection: close\r\n" % [ status.to_i, status.to_i])
      headers.each do |key,value|
        socket.write("#{key}: #{value}\r\n")
      end
      socket.write "\r\n"
      socket.write(body.read)
    end
  end

  Rack::Handler.register :miniserver, Server
end

# @private
# :nodoc:
class TCPServer
  def initialize_with_backlog(*args)
    initialize_without_backlog(*args)
    listen(1024)
  end

  alias_method :initialize_without_backlog, :initialize
  alias_method :initialize, :initialize_with_backlog
end
