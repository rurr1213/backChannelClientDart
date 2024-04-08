import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import '../ftlTools/network/TcpMgr.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/HyperCubeMessagesCommon_generated.dart';
import '../ftlTools/network/SerDes.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/Logger.dart';
import '../ftlTools/network/Packet.dart';
import 'SignallingObject.dart';

const String PRIMARY_SERVERNAME = "primary.hyperkube.net";
const String SECONDARY_SERVERNAME = "secondary.hyperkube.net";
const int DEFAULT_SERVERPORT = 5054;

class HyperCubeServerAddress {
  String hostName;
  String ip = "";
  int port;
  HyperCubeServerAddress.set(this.hostName, this.port);
  set(_name, _port) {
    hostName = _name;
    port = _port;
  }
}

class HyperCubeServerAddressPrimary extends HyperCubeServerAddress {
  HyperCubeServerAddressPrimary()
      : super.set(PRIMARY_SERVERNAME, DEFAULT_SERVERPORT);
}

class HyperCubeServerAddressSecondary extends HyperCubeServerAddress {
  HyperCubeServerAddressSecondary()
      : super.set(SECONDARY_SERVERNAME, DEFAULT_SERVERPORT);
}

class HyperCubeServerAddresses {
  HyperCubeServerAddressPrimary primary = HyperCubeServerAddressPrimary();
  HyperCubeServerAddress secondary = HyperCubeServerAddressSecondary();
  HyperCubeServerAddresses.set(this.primary, this.secondary);
  HyperCubeServerAddresses();
  HyperCubeServerAddresses.setDetail(String _primary, int _primaryPort,
      String _secondary, int _secondaryPort) {
    primary.set(_primary, _primaryPort);
    primary.set(_secondary, _secondaryPort);
  }
}

class HyperCubeClient {
  final Logger logger;
  final TcpManager tcpManager;
  SignallingObject? signallingObject;
  bool connectionOpen = false;
//  String ipAddress = "";
//  int ipPort = 0;
  int numConnectionAttempts = 0;
  int numSentMsgs = 0;
  int numRecvMsgs = 0;
  Timer? connectionTimer;
  int _connectionPeriodSecs = 10;
  String connectedGroupName = "";
  bool alreadyWarnedOfConnectFailure = false;
  HyperCubeServerAddresses serverAddresses = HyperCubeServerAddresses();
  HyperCubeServerAddress activeServerAddress = HyperCubeServerAddressPrimary();

  HyperCubeClient(this.logger) : tcpManager = TcpManager("Hyper", logger) {
    signallingObject = SignallingObject(logger, this);
  }

  Future<bool> dnsLookup(HyperCubeServerAddress _hyperCubeServerAddress) async {
    try {
      final result = await InternetAddress.lookup(
          _hyperCubeServerAddress.hostName,
          type: InternetAddressType.IPv4);
      if (!result.isNotEmpty) {
        logger.add(EVENTTYPE.WARNING, "HyperCubeClient::dnsLookup()",
            "lookup of $_hyperCubeServerAddress failed");
        return false;
      }
      InternetAddress internetAddress = result[0];
      logger.add(EVENTTYPE.INFO, "HyperCubeClient::dnsLookup()",
          "lookup of $_hyperCubeServerAddress returned ${internetAddress.address}");
      _hyperCubeServerAddress.ip = internetAddress.address;
      return true;
    } catch (e) {
      logger.add(EVENTTYPE.NOTE, "HyperCubeClient::dnsLookup()",
          "lookup of $_hyperCubeServerAddress failed. Not found");
      return false;
    }
  }

  Future<bool> openConnection() async {
    connectionTimer = null;

    if (!tcpManager.isOpen()) {
      if (!await dnsLookup(activeServerAddress)) return false;

      connectionOpen = await tcpManager.open(onTcpReceive, onTcpClose,
          activeServerAddress.ip, activeServerAddress.port, false);

      logger.setStateInt(
          "HyperCubeClient-NumConnectionAttempt", ++numConnectionAttempts);
      logger.setStateString("HyperCubeClient-ConnectionState",
          connectionOpen ? "connected" : "disconnected");

      if (connectionOpen) {
        logger.add(EVENTTYPE.INFO, "HyperCubeClient::openConnection()",
            "Opened connection to $activeServerAddress.ip:$activeServerAddress.port");
        alreadyWarnedOfConnectFailure = false;
        onConnection();
      } else {
        if (!alreadyWarnedOfConnectFailure)
          logger.add(EVENTTYPE.WARNING, "HyperCubeClient::openConnection()",
              "connection failed to $activeServerAddress.ip:$activeServerAddress.port");
        alreadyWarnedOfConnectFailure = true;
      }
    }

    // if open fails, rotate servers fir next attempt
    if (connectionOpen == false) {
      if (activeServerAddress == serverAddresses.primary) {
        activeServerAddress = serverAddresses.secondary;
      } else {
        activeServerAddress = serverAddresses.primary;
      }
    }

    return connectionOpen;
  }

  onConnectionTimer(Timer timer) async {
    if (!connectionOpen) {
      connectionOpen = await openConnection();
    } else {
      timer.cancel();
    }
  }

  startPeriodicConnectionAttempts([bool startNow = false]) {
    connectionTimer = Timer.periodic(
        Duration(seconds: _connectionPeriodSecs), onConnectionTimer);
    if (startNow) {
      onConnectionTimer(Timer(Duration.zero, () {}));
    }
  }

  bool onConnection() {
    numRecvMsgs = 0;
    numSentMsgs = 0;
    signallingObject!.onConnection();
    return true;
  }

  bool onDisconnection() {
    signallingObject!.onDisconnection();
    return true;
  }

  onConnectionDataOpen(String _groupName) {
    connectedGroupName = _groupName;
  }

  onConnectionDataClosed() {}

  bool init(ConnectionInfo connectionInfo,
      {HyperCubeServerAddresses? paramServerAddresses}) {
    if (paramServerAddresses != null) {
      serverAddresses = paramServerAddresses;
    }
    activeServerAddress = serverAddresses.primary;
    setConnectionInfo(connectionInfo);
    startPeriodicConnectionAttempts(true);
    return true;
  }

  deinit() {
    connectionTimer!.cancel();
    tcpManager.close();
  }

  bool subscribe(String groupName) {
    return signallingObject!.subscribe(groupName);
  }

  bool unsubscribe(String groupName) {
    return signallingObject!.unsubscribe(groupName);
  }

  dynamic onTcpReceive(Uint8List event) {
    Packet packet = Packet(event);
    onPacket(packet);
  }

  onPacket(Packet packet) {}

  onMsg(MsgExt msg) {
    logger.setStateInt("HyperCubeClient-NumRecvMsgs", ++numRecvMsgs);
  }

  bool checkReadyToOpenForData() {
    if (signallingObject!.state != SignallingObjectState.subscribed) {
      logger.add(EVENTTYPE.ERROR, "HyperCubeClient::checkReadyToOpenForData()",
          "inCorrect state  ${signallingObject!.state} ");
      return false;
    }
    return true;
  }

  bool checkReadyForData() {
    if (signallingObject!.state != SignallingObjectState.inDataState) {
      logger.add(EVENTTYPE.ERROR, "HyperCubeClient::checkReadyForData()",
          "inCorrect state  ${signallingObject!.state} ");
      return false;
    }
    return true;
  }

  setStateAsData(bool yes) {
    SignallingObjectState state = signallingObject!.state;
    SignallingObjectState prevState = state;
    if (yes) {
      switch (signallingObject!.state) {
        case SignallingObjectState.openForData:
          state = signallingObject!.state = SignallingObjectState.inDataState;
          logger.add(EVENTTYPE.INFO, "HyperCubeClient::setStateAsData()",
              " set state as in Data state:$prevState>$state");
          break;
        default:
          logger.add(EVENTTYPE.WARNING, "HyperCubeClient::setStateAsData()",
              "inCorrect state  ${signallingObject!.state} ");
          break;
      }
    } else {
      switch (signallingObject!.state) {
        case SignallingObjectState.disconnected:
        case SignallingObjectState.closedForData:
        case SignallingObjectState.inDataState:
          state =
              signallingObject!.state = SignallingObjectState.outOfDataState;
          logger.add(EVENTTYPE.INFO, "HyperCubeClient::setStateAsData()",
              " set state as in Data state:$prevState>$state");
          break;
        default:
          logger.add(EVENTTYPE.WARNING, "HyperCubeClient::setStateAsData()",
              "inCorrect state  ${signallingObject!.state} ");
          break;
      }
    }
    return true;
  }

  dynamic onTcpClose() {
    logger.add(EVENTTYPE.WARNING, "HyperCubeClient::onTcpClose()",
        "connection to ${activeServerAddress.hostName}:${activeServerAddress.port} closed");
    onDisconnection();
    connectionOpen = false;
    logger.setStateString("HyperCubeClient-ConnectionState",
        connectionOpen ? "connected" : "disconnected");
    startPeriodicConnectionAttempts(); // try again
  }

  bool sendBinary(List<int> data, [int size = 0]) {
    logger.setStateInt("HyperCubeClient-NumSentMsgs", ++numSentMsgs);
    return tcpManager.sendBinary(data, size);
  }

  bool sendMsg(Msg msg) {
    const int bufferSize = 1024 * 8;
    Uint8List data = Uint8List(bufferSize);
    SerDes sd = SerDes(data);
    int size = msg.serialize(sd);
    sendBinary(data, size);
    assert(size < bufferSize); // else buffer is too small
    return size != 0;
  }

  setConnectionInfo(ConnectionInfo connectionInfo) {
    signallingObject!.connectionInfo = connectionInfo;
  }

  bool onGroupInfoList(List<GroupInfo> _groupInfoList) {
    _groupInfoList.forEach((element) {
      GroupInfo groupInfo = element;
      String name = groupInfo.groupName;
      logger.add(EVENTTYPE.INFO, "HyperCubeClient::onGroupInfoList()",
          " groupInfo name: $name groupInfo: ${groupInfo.toJson().toString()} ");
    });
    return true;
  }

  bool onLogLines(LineList _lineList) {
    return true;
  }

  bool onStatusLines(LineList _lineList) {
    return true;
  }

  bool getConnectionInfo(List<String> _list) {
    Map<String, dynamic> _map = signallingObject!.connectionInfoAck.toJson();
    _map.forEach((key, value) {
      _list.add("$key:$value");
    });

    return true;
  }
}
