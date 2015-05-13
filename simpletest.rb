require 'json'
require 'socket'
require_relative 'peerChat'


ip = "127.0.0.1"
id = "NILID"

puts "*-----------------------*"
puts "This will take a few minutes"
puts "*-----------------------*"
puts "Adding some nodes"
puts "*-----------------------*"

anode = PeerChatInterface.new("ANODE")
sA = UDPSocket.new
sA.bind(ip, 8777)
anode.init( sA, InetAddr.new( "127.0.0.1", "8777" ) )
anid = anode.joinNetwork( InetAddr.new( nil, nil ), "Anode" )

sleep 1

bnode = PeerChatInterface.new("BNODE")
sB = UDPSocket.new
sB.bind(ip, 8778)
bnode.init( sB, InetAddr.new( "127.0.0.1", "8778" ) )
nid = bnode.joinNetwork( InetAddr.new("127.0.0.1", "8777"), "Bnode" )

sleep 1

cnode = PeerChatInterface.new("CNODE")
sC = UDPSocket.new
sC.bind(ip, 8779)
cnode.init( sC, InetAddr.new( "127.0.0.1", "8779" ) )
nid = cnode.joinNetwork( InetAddr.new( "127.0.0.1", "8778" ), "Cnode" )

sleep 10
puts "*-----------------------*"

puts "Chatting some information"

puts "*-----------------------*"


anode.chatPage( "I love Anode", ["Anode"] )
anode.chatPage( "I love Bnode", ["Bnode"] )

bnode.chatPage( "Do you like Bnode", ["Bnode"] )

cnode.chatPage( "I love Anode and Bnode", ["Bnode", "Anode"] )


sleep 20
puts "*-----------------------*"

puts "Lets Search for some node with tags"

puts "*-----------------------*"

cnode.chat_retrieve( ["Anode"] )

sleep 20
puts "*-----------------------*"

puts "Testing to chat with nodes that 1) don't exist and 2) have left the network"

puts "*-----------------------*"

anode.leaveNetwork( anid )
sleep 1

cnode.chatPage( "Hello,everyone", ["Anode", "Znode"] )

sleep 4

input = ""
while input != 'LEAVE'
  input = gets.chomp()
end



