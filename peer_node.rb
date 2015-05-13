require 'json'
require 'socket'
require_relative 'peerChat'

puts "Peer starts"
ip = "127.0.0.1"
id = "NILID"


puts "JOINING_NETWORK first.Please enter node_name:"
nodeNM = gets


puts "Set your unique port:"
peerPort = gets.to_i

puts "Enter a tag:"
peerTag = gets
puts "New peer joins in network..."


node = PeerChatInterface.new(nodeNM)
socket = UDPSocket.new
socket.bind(ip, peerPort)
node.init(socket, InetAddr.new("127.0.0.1", peerPort))
node_nid = node.joinNetwork(InetAddr.new("127.0.0.1", "8777"), peerTag) #connect through gateway

# can also connect through other known node.
# node_nid = node.joinNetworkInetAddr.new("127.0.0.1", "port of known node", peerTag )

sleep 20
loop{
  puts "Please choose the message type:"
  typeMsg = ""
  typeMsg = gets.chomp()
  puts typeMsg
  if typeMsg == "CHAT"
      puts "Please enter indexed Tag:"
      tTag = ""
      tTagA = [gets.chomp()]

      puts "Please enter chat text:"
      chatText = gets.chomp()
      puts "Start chatting ..."

      node.chatPage(chatText, tTagA)

    elsif typeMsg == "CHAT_RETRIEVE"
      puts "Please enter your target tag:"
      tTag = ""
      tTagA = [gets.chomp()]


      puts "Start chat_retrieving..."

      node.chat_retrieve(tTagA)

    elsif typeMsg == "LEAVING_NETWORK"
      node.leaveNetwork(node_nid)

      puts "Node leaves network..."

    else
      puts "No matching type.."

    sleep 40
  end
}


input = ""
while input != 'LEAVE'
  input = gets.chomp()
end



