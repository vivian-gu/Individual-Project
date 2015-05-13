# Individual-Project

JINWEI GU 14306748 CS7050 PeerChat Project

Run the simple test - navigate to directory containing files and enter "ruby simpletest.rb"
Note: In simpletest, each node could join in the network through any node which is already exist in the network. 
The new peer want to join in only need know one node's ip and port.

Implementation of interface is in file PeerChat.rb

Routing is based on Pastry paper without the leaf or neighbourhood parts

Target_id has been removed from both join and join_relay messages since the routing has no need for it.


The system could also be tested with peer_node.rb

This test's joining is based on static gateway. Run the gatewayset.rb first - "ruby gatewayset.rb"

And then could run peer_node.rb in seperate command lines to create different peers with different port on one machine.

But due to the time constraints, there is still some problems with the code in peer_node.rb.


In a word, all required functions are mostly implemented with PeerchatInterface in PeerChat.rb.
