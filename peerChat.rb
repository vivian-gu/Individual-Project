require 'json'
require 'socket'


InetAddr = Struct.new(:ip, :port) # Struct for inetAddr
NodeAddr = Struct.new(:guid, :ip, :port) # Same as above but including GUID

class PeerChatInterface

  attr_accessor :name
  # Initialization of variables
  def initialize(name_input)
    @name = name_input # Stores the name of the node
    @socket = nil # Socket
    @localInetAddr = nil # IP & port of node
    @id = "NILID"
    @guid = "NILGUID" # GUID has of ID
    @routing_table = Hash.new

    @m_max = 32 # log2b(L)
    @n_max = 16 # 2^b
    @b = 4 # hex
    @clength = 32
    @bitlength = 128 # bit length of GUID
    @gateway_table = {}
    # while its routing information is initialised
    @next_nid = 0
    @postHash = []


    @chat_retrieveAckWait = {} # Hash to temporarily store chat responce info
    @chatAckWait = {} # Hash to temporarily store chat ACK info
    @checkAckWait = {} # Hash to temporarily store ping ACK info
    @netWorkMember = false # flag to check if node is a member of network, resets to false when we leave
  end

  # Initialization of node
  def init(udp_socket, inetAddr_in)
    @socket = udp_socket # Assign socket
    self.listenLoop() # Set up a new thread to listen for incoming messages
    @localInetAddr = inetAddr_in # Store our local address
  end

  def PadGUID(guid_in)
    guid_in = guid_in.to_s(16)
    pad_amount = @clength - guid_in.length
    for i in 0..pad_amount-1
      guid_in = "0" + guid_in
    end
    return guid_in
  end

  def Hash_Func(str)
    hash = 0
    i = 0
    while i < str.length
      c = str[i]
      hash = hash * 31 + c.ord
      i = i + 1
    end
    hash = hash.abs
    return PadGUID(hash)
  end

  #-------------------------------------------------------------------------------------------------------------------
  # nextHop() method helps to find the next hop for a message and is based on the PASTRY paper
  # It reads through all characters in both GUIDs to find the first differing one and sets this digits location as M
  # N is the value of the target_id (actually a GUID) at this digit
  #-------------------------------------------------------------------------------------------------------------------

  def nextHop(target_id)
    m = 0
    n = -1
    while @guid[m] == target_id[m] && m < @m_max
      m += 1
    end
    n = target_id[m]
    n = n.to_s
    n = n.hex

    # Checking routing table at that location to see if has an entry
    # If has,the entry will be a digit closer than the current nodes GUID
    if @routing_table[[0, m, n]] != nil
      return InetAddr.new(@routing_table[[0, m, n]][:ip_address], @routing_table[[0, m, n]][:port]), m, n

    # If not,searching the entire routing table for the entry with the GUID closest to the target_id
    else
      shortestDistance = distancing(target_id, @guid)
      # Sending message on if there is a closer address
      nh = InetAddr.new()
      @routing_table.each do |key, array|   # Accessing each element of routing table
        if distancing(target_id, array[:node_id]) < shortestDistance && distancing(target_id, array[:node_id]) != 0
          shortestDistance = distancing(target_id, array[:node_id])
          nh.ip = array[:ip_address]
          nh.port = array[:port]
        end
      end
      return nh, m, n
    end
  end

  #Also return the GUID of next hop node
  def nextCheckHop(target_id)
    nh, m, n = nextHop(target_id)
    return NodeAddr.new(@routing_table[[0, m, n]][:node_id], nh.ip, nh.port), m, n
  end

  # Only getting M and N
  def getMnN(target_id)
    m = 0
    n = -1
    while @guid[m] == target_id[m] && m < @m_max
      m += 1
    end
    n = target_id[m]
    n = n.to_s
    n = n.hex
    return m, n
  end

  # The difference between own GUID and another GUID
  def differing(node_guid)
    iGuid = @guid.hex
    iNodeGuid = node_guid.hex
    t = iGuid - iNodeGuid
    return t.abs
  end

  # The distance between two different GUIDs (not own)
  def distancing(guid_1, guid_2)
    guid_1 = guid_1.hex
    guid_2 = guid_2.hex
    t = guid_1 - guid_2
    return t.abs
  end

=begin
  halfDiffering() function returns the difference between a nodes GUID and the GUID that would be half way between
  our GUID and a GUID with the differing digit being one higher or lower depending on whether the target GUID is
  higher or lower than this nodes GUID
=end
  def halfDiffering(node_id)
    half_id = node_id.dup # Need to hard copy
    m = 0
    while @guid[m] == node_id[m] && m < @m_max
      m += 1
    end
    if m > 30
      return -1
    end
    m += 1
    half_id[m] = "8"
    m += 1
    while m < @m_max
      half_id[m] = "0"
      m += 1
    end
    t = half_id.hex - node_id.hex
    return t.abs
  end


  # routeInfo function takes routing information from passing messages and sees if it can be used in our routing table
  def routeInfo(routeTable)
    for addr in routeTable
      addr2 = {:node_id => addr["node_id"], :ip_address => addr["ip_address"], :port => addr["port"]}
      m, n = getMnN(addr["node_id"])
      if @routing_table.has_value?(addr)
        if halfDiffering(@routing_table[[0, m, n]]["node_id"]) < halfDiffering(@routing_table[[0, m, n]]["node_id"])
          @routing_table[[0, m, n]] = addr2
        end
      else
        @routing_table[[0, m, n]] = addr2
      end
    end
  end

  # Removes an entry from the routing table if it has a node_id, used for trimming dead link
  def removeAddr(node_id)
    for addr in @routing_table.keys
      if @routing_table[addr]["node_id"] == node_id
        @routing_table.delete([addr])
      end
    end
  end

=begin
  # Send message to all nodes in routing table of node except messages with the node ID contain in <blank>
  # <blank> may be nil for a true broadcast
=end
  def sendBroadCast(blank, msg)
    for addr in @routing_table.keys
      if @routing_table[addr]["node_id"] != blank
        @socket.send msg, 0, @routing_table[addr]["ip_address"], @routing_table[addr]["port"]
      end
    end
  end

  #-------------------------------------------------------------------------------------------------------------------
  # JOINING NETWORK FUNCTION
  #-------------------------------------------------------------------------------------------------------------------

  def joinNetwork(bootstrapInetAddr_in, id_in)
    @netWorkMember = true
    @id = id_in
    @bootstrapInetAddr = bootstrapInetAddr_in
    @guid = Hash_Func(@id)
    for m in 0..@guid.length
      n = @guid[m].to_i
      @routing_table[[0, m, n]] = {:node_id => @guid, :ip_address => @localInetAddr.ip, \
       :port => @localInetAddr.port}
    end
    if bootstrapInetAddr_in.ip == nil
      puts @id, "First Node in Network!  Waiting for peers ..."
      return @next_nid
    else
      joinMsg = {:type => "JOINING_NETWORK", :node_id => @guid, \
                   :ip_address => @localInetAddr.ip, :port => @localInetAddr.port}.to_json
      @socket.send joinMsg, 0, @bootstrapInetAddr.ip, @bootstrapInetAddr.port
      return @next_nid
    end
    @next_nid += 1
  end

  #-------------------------------------------------------------------------------------------------------------------
  # LEAVING NETWORK
  # if not empty, broadcasting to all nodes
  #-------------------------------------------------------------------------------------------------------------------
  def leaveNetwork(network_id)
    if @routing_table.empty?
      puts "You may not leave the network as you are the sole bootstrap node"
    else
      leaveMsg = {:type => "LEAVING_NETWORK", :node_id => @guid}.to_json
      sendBroadCast(nil, leaveMsg)
      @routing_table = Hash.new()
      @netWorkMember = false
    end

  end

  #-------------------------------------------------------------------------------------------------------------------
  # Checking a route with creating a new thread
  # Sends a ping message and waits 10 seconds for a response from the next hop
  # If this response is not received it calls remove on the address that failed
  # Uses a flag to avoid check same route. @checkAckWait = 0 for free flag
  # = 1 indicates check in progress while 2 represents ack received
  #-------------------------------------------------------------------------------------------------------------------

  def routeChecker(target_id)
    Thread.new {
      pingMsg = {:type => "PING", :target_id => target_id, :sender_id => @guid, :ip_address => @localInetAddr.ip, \
       :port => @localInetAddr.port}.to_json
      nh, m, n = nextCheckHop(target_id)
      if nh.ip != nil
        @socket.send pingMsg, 0, nh.ip, nh.port
        t = Time.now.sec
        t2 = t + 10
        @checkAckWait[nh.guid] = 0
        while t < t2
          if @checkAckWait[nh.guid] == 2
            break
          end
          k = Time.now.sec
          if k != t
            t += 1
          end
        end
      end
      removeAddr(nh.guid)
    }
  end


  #-------------------------------------------------------------------------------------------------------------------
  # Send a text to the nodes with the unique tags
  # Creating a new thread for each unique tag
  # This thread will then send an CHAT message to the valid target & keep checking a temporary variable that stores the CHAT_ACK messages
  #-------------------------------------------------------------------------------------------------------------------

  def chatPage(text, unique_tags)
    y = unique_tags.length - 1
    for i in 0..y
      Thread.new(i) { |i2|
        tagHash = Hash_Func(unique_tags[i2])

        while @chatAckWait != nil && @chatAckWait[tagHash] != nil && \
         (@chatAckWait[tagHash] == 1 || @chatAckWait[tagHash] == 2)
        end
        @chatAckWait[tagHash] = 1 # Set flag guarding chat messages for this node to 1
        chatMsg = {:type => "CHAT", :target_id => tagHash, :sender_id => @guid, :keytag => unique_tags[i2],
                   :post => text}.to_json
        nh, m, n = nextHop(tagHash)
        if tagHash == @guid
          # Just send the message to our own respond without actually sending
          chatMsg = JSON.parse(chatMsg)
          respond(chatMsg)
          @chatAckWait[tagHash] = 0
          return
        end
        @socket.send chatMsg, 0, nh.ip, nh.port
        t = Time.now.sec    # Wait 30 seconds for response
        t2 = t + 250
        while t < t2
          if @chatAckWait[tagHash] == 2    # If a flag indicates response break
            break
          end
          k = Time.now.sec
          if k != t
            t += 1
          end
        end

        if @chatAckWait[tagHash] != 2
          puts " "
          print @name, "  Get no acknowledgment in checking route"
          puts " "
          routeChecker(tagHash)
        else
          puts " "
          print @name, "Successful Chat!"
          puts " "
        end
        @chatAckWait[tagHash] = 0
      }
    end
  end

  # Creates chat_retrieve
  # Creates new thread for whole chat_retrieve
  # For each unique tag creates it's own thread and sends off a chat_retrieve message and waits for a responce
  # Identical to CHAT function above if no responce received after 30 seconds checks route
  # All responces are stored temporarily once they are received and after 3 second the overall thread return available
  # results
  def chat_retrieve(unique_tags)
    Thread.new {
      tagHash = []
      tempResults = {}
      list = {}
      y = unique_tags.length - 1
      for i in 0..y
        Thread.new(i) { |i2|
          tagHash[i2] = Hash_Func(unique_tags[i2])
          while @chat_retrieveAckWait != nil && (@chat_retrieveAckWait[tagHash[i2]] == 1 || @chat_retrieveAckWait[tagHash[i2]].kind_of?(Array))
          end
          @chat_retrieveAckWait[tagHash[i2]] = 1
          chat_retrieveMsg = {:type => "CHAT_RETRIEVE", :tag => unique_tags[i2], :node_id => tagHash[i2], :sender_id => @guid}.to_json
          nh, m, n = nextHop(tagHash[i2])
          @socket.send chat_retrieveMsg, 0, nh.ip, nh.port
          t = Time.now.sec
          t2 = t + 90
          while t < t2 # Waits 30 seconds before checking route
            if @chat_retrieveAckWait[tagHash[i2]].kind_of?(Array)
              tempResults[tagHash[i2]] = @chat_retrieveAckWait[tagHash[i2]]
              break
            end
            t = Time.now.sec
            if t < t2 - 30
              t = t + 60
            end
          end
          if @chat_retrieveAckWait[tagHash[i2]].kind_of?(Array)
            puts "Get correct chat result"
          else
            puts "The chat_retrieve failed to check the route within set time"

            routeChecker(tagHash[i2])
          end
          @chat_retrieveAckWait[tagHash[i2]] = 0
        }
      end
      t3 = Time.now.sec   # returns results after 3 seconds
      t4 = t3 + 3
      while t3 < t4
        t3 = Time.now.sec
        if t3 < t4 - 3
          t3 = t3 + 60
        end
      end

      list = tempResults[tagHash[0]]
      removeList = []
      for j in 1..tagHash.length-1
        nList = tempResults[tagHash[j]]
        list.each { |h|
          removeFlag = true
          nList.any? { |nH|
            if nH[:text] == h[:text]
              removeFlag = false

            end
          }
          if removeFlag
            removeList << h
          end
        }
        for k in removeList
          list.delete(k)
        end
      end
      r = ChatResult.new()   # Holds results
      r.tags = unique_tags
      r.resutls = list
      return r
    }
  end

  #-------------------------------------------------------------------------------------------------------------------
  # listenLoop() function creates a new thread that listening to incoming messages
  # Checks this node is still a member of a network and then calls respond to handle the messages
  #-------------------------------------------------------------------------------------------------------------------

  def listenLoop()
    x = Thread.new {
      i = 0
      while true
        i = i + 1
        puts " "
        print @name, " Listen Loop Round: ", i
        puts " "
        jsonIN = @socket.recv(65536)
        puts " "
        print @name, " ", Time.now, " has received a Message: ", jsonIN
        puts " "
        parsed = JSON.parse(jsonIN)
        if @netWorkMember
          self.respond(parsed)
        else
          puts "Not a member of a Network, No Response"
        end
      end
    }
  end

  #-------------------------------------------------------------------------------------------------------------------
  # RESPOND FUNCTION
  # This function handles incoming messages
  #-------------------------------------------------------------------------------------------------------------------

  def respond(message)
=begin
    If a joining message adds address to routing table and gateway table before sending a routing info message
    to it and a joining relay message to a node with a GUID closer to the joining node
=end
    if message["type"] == "JOINING_NETWORK"
      tnh, tm, tn = nextHop(message["node_id"])
      @gateway_table[message["node_id"]] = {:ip_address => message["ip_address"], :port => message["port"]}
      if @routing_table.has_key?([0, tm, tn]) == false
        @routing_table[[0, tm, tn]] = {:node_id => message["node_id"], :ip_address => message["ip_address"], \
         :port => message["port"]}
      end
      if tnh.ip != nil
        joinMsgRelay = {:type => "JOINING_NETWORK_RELAY", :node_id => message["node_id"], \
         :gateway_id => @guid, :ip_address => message["ip_address"], \
         :port => message["port"]}.to_json
        @socket.send joinMsgRelay, 0, tnh.ip, tnh.port
      end
      tempRouteTable = []
      @routing_table.each_value { |addr|
        tempRouteTable.push(addr)
      }
      routingInfoMsg = {:type => "ROUTING_INFO", :gateway_id => @guid, :node_id => message["node_id"], \
       :ip_address => @localInetAddr.ip, :port => @localInetAddr.port, :route_table => tempRouteTable}.to_json
      @socket.send routingInfoMsg, 0, message["ip_address"], message["port"]
    end

    if message["type"] == "JOINING_NETWORK_RELAY"
      tnh, tm, tn = nextHop(message["node_id"])
      nh, gm, gn = nextHop(message["gateway_id"])
      if @routing_table.has_key?([0, tm, tn]) == false
        #puts "h6"
        @routing_table[[0, tm, tn]] = {:node_id => message["node_id"], :ip_address => message["ip_address"], \
         :port => message["port"]}
      end
      if tnh.ip != nil
        joinMsgRelay = {:type => "JOINING_NETWORK_RELAY", :node_id => message["node_id"], \
         :gateway_id => message["gateway_id"], \
          :ip_address => message["ip_address"], :port => message["port"]}.to_json
        @socket.send joinMsgRelay, 0, tnh.ip, tnh.port
      end
      tempRouteTable = []
      @routing_table.each_value { |addr|
        tempRouteTable.push(addr)
      }
      routingInfoMsg = {:type => "ROUTING_INFO", :gateway_id => message["gateway_id"], :node_id => message["node_id"], \
       :ip_address => @localInetAddr.ip, :port => @localInetAddr.port, :route_table => tempRouteTable}.to_json
      if nh.ip != nil
        @socket.send routingInfoMsg, 0, nh.ip, nh.port
      end
    end

=begin
    when getting a routing info message extract as much useful information out of it as we can and forward it onto the
    intended target node unless it was intended for our node
=end
    if message["type"] == "ROUTING_INFO"
      routeInfo(message["route_table"])
      if message["node_id"] == @guid
        return
      elsif message["gateway_id"] == @guid
        if @gateway_table.has_key?(message["node_id"])
          p @socket.send message.to_json, 0, @gateway_table[message["node_id"]][:ip_address].to_s, @gateway_table[message["node_id"]][:port]
        else
          puts "Routing_Info message receave error not key in gatewayTable!"
        end
      else
        nh, gm, gn = nextHop(message["node_id"])
        message = message.to_json
        if nh.ip != nil
          @socket.send message, 0, nh.ip, nh.port
        end
      end
    end

    # If get a leaving message, remove the node from the network
    if message["type"] == "LEAVING_NETWORK"
      removeAddr(message["node_id"])
    end

    # When receive an chat message,check if it is intended for
    # If not, forward to next hop
    if message["type"] == "CHAT"
      if message["target_id"] == @guid
        flag = true
        for i in 0..@postHash.length-1
          if @postHash[i][:text] == message["post"]
            flag = false
          end
        end
        if flag
          @postHash << {:text => message["post"]}
        end
        ackChatMsg = {:type => "ACK_CHAT", :node_id => message["sender_id"], :keytag => message["keytag"]}.to_json
        if message["sender_id"] == @guid
          puts " "
          print @name, "CHATTING WITH YOURSELF" # If processes own chatting message, no need to send an ACK
          puts " "
          return
        end
        nh, sm, sn = nextHop(message["sender_id"])
        @socket.send ackChatMsg, 0, nh.ip, nh.port
      else
        nh, tm, tn = nextHop(message["target_id"])
        if nh.ip != nil
          @socket.send message.to_json, 0, nh.ip, nh.port
        end
      end
    end


    # Keep forwarding until this ACK_CHAT message reaches its destination
    if message["type"] == "ACK_CHAT"
      if message["node_id"] == @guid
        tagHash = Hash_Func(message["keytag"])
        @chatAckWait[tagHash] = 2
      else
        nh, m, n = nextHop(message["node_id"])
        if nh.ip != nil
          @socket.send message.to_json, 0, nh.ip, nh.port
        end
      end
    end


=begin
    Keep forwarding chat_retrieve message until it reaches correct location in which case appending @postHash to a
    chat response message and send it to the sender ID
=end
    if message["type"] == "CHAT_RETRIEVE"
      if message["node_id"] == @guid
        chatresponse_msg = {:type => "CHAT_RESPONSE", :tag => message["tag"], :node_id => message["sender_id"],
                            :sender_id => @guid, :response => @postHash}.to_json
        nh, sm, sn = nextHop(message["sender_id"])
        @socket.send chatresponse_msg, 0, nh.ip, nh.port
      else
        nh, tm, tn = nextHop(message["node_id"])
        message = message.to_json
        if nh.ip != nil
          @socket.send message, 0, nh.ip, nh.port
        end
      end
    end

=begin
    Keep forwarding response until reach intended recipient and then put results in flag.
    Original chat_retrieve thread can process the results
=end
    if message["type"] == "CHAT_RESPONSE"
      if message["node_id"] == @guid
        @chat_retrieveAckWait[message["sender_id"]] = message["response"]
      else
        nh, tm, tn = nextHop(message["node_id"])
        if nh.ip != nil
          @socket.send message.to_json, 0, nh.ip, nh.port
        end
      end
    end

    # Upon receiving a PING, sending to next hop and generating ACK
    if message["type"] == "PING"
      ackMsg = {:type => "ACK", :node_id => @guid, :ip_address => @localInetAddr.ip, \
       :port => @localInetAddr.port}.to_json
      @socket.send ackMsg, 0, message["ip_address"], message["port"]
      if message["target_id"] != @guid
        #puts @name, "PNH", message["target_id"], Time.now
        nh, m, n = nextHop(message["target_id"])
        if nh.ip != nil
          message["ip_address"] = @localInetAddr.ip
          message["port"] = @localInetAddr.port
          @socket.send message.to_json, 0, nh.ip, nh.port
        end
      end
    end

    # Receiving an ACK message proves the node is still alive
    if message["type"] == "ACK"
      @checkAckWait[message["node_id"]] = 2
    end
  end
end

#-------------------------------------------------------------------------------------------------------------------
# Class that returns chat results
#-------------------------------------------------------------------------------------------------------------------
class ChatResult
  tags = nil
  result = nil
end