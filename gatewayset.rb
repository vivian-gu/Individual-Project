require 'json'
require 'socket'
require_relative 'peerChat'


ip = "127.0.0.1"
id = "NILID"

# Set bootstrap node
bootstrap = PeerChatInterface.new("GATEWAY")
socketBT = UDPSocket.new
socketBT.bind(ip, 8777)
bootstrap.init( socketBT, InetAddr.new( "127.0.0.1", "8777" ) )
bnid = bootstrap.joinNetwork( InetAddr.new( nil, nil ), "bootstrap_node" )

puts "bootstrap node established, the address is (ip:127.0.0.1,port:8777)"

input = ""
while input != 'LEAVE'
  input = gets.chomp()
end

