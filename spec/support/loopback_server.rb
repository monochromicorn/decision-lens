require "socket"

# A throwaway HTTP/1.1 server bound to 127.0.0.1 only, used to exercise the real
# Net::HTTP transport without any external network. Records every request.
class LoopbackServer
  Request = Struct.new(:method, :path, :headers, :body)

  attr_reader :requests

  def initialize(status: 200, body: "{}", delay: 0)
    @status = status
    @body = body
    @delay = delay
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { serve }
  end

  def url = "http://127.0.0.1:#{@server.addr[1]}"

  def stop
    @thread.kill
    @server.close
  end

  private

  def serve
    loop do
      client = @server.accept
      Thread.new(client) { |socket| handle(socket) }
    end
  rescue IOError
    nil
  end

  def handle(socket)
    method, path = socket.gets.to_s.split
    headers = {}
    while (line = socket.gets) && line != "\r\n"
      name, value = line.chomp.split(": ", 2)
      headers[name.downcase] = value
    end
    body = socket.read(headers["content-length"].to_i).to_s
    @requests << Request.new(method, path, headers, body)
    sleep @delay
    socket.write("HTTP/1.1 #{@status} X\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{@body.bytesize}\r\nConnection: close\r\n\r\n#{@body}")
  rescue Errno::EPIPE, Errno::ECONNRESET, IOError
    nil
  ensure
    socket.close unless socket.closed?
  end
end
