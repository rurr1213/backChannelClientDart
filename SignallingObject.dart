import 'dart:convert';

import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/HyperCubeMessagesCommon_generated.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/Logger.dart';
import 'HyperCubeClient.dart';

enum SignallingObjectState {
  instantiated,
  connected,
  subscribed,
  openForData,
  inDataState,
  outOfDataState,
  closedForData,
  disconnected
}

class SignallingObject {
  final Logger logger;
  final HyperCubeClient hyperCubeClient;
  int numRemotePingAcks = 0;
  int numRemotePings = 0;
  int _systemId = 0;
  SignallingObjectState state = SignallingObjectState.instantiated;
  ConnectionInfo connectionInfo = ConnectionInfo();
  ConnectionInfoAck connectionInfoAck = ConnectionInfoAck();

  SignallingObject(this.logger, this.hyperCubeClient);

  setSystemId(int systemId) => _systemId = systemId;

  bool onConnectionInfoAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;

    connectionInfoAck.fromJson(hyperCubeCommand.jsonData);

    String alternateHyperCubeIp = connectionInfoAck.alternateHyperCubeIp;
    state = SignallingObjectState.connected;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onConnectionInfoAck()",
        " received onConnectionInfoAck status:$_status, alternateIp: $alternateHyperCubeIp state:$prevState>$state");
    return true;
  }

  bool onCreateGroupAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;

    GroupInfo groupInfo = GroupInfo();
    groupInfo.fromJson(hyperCubeCommand.jsonData);

    logger.add(EVENTTYPE.INFO, "SignallingObject::onCreatGroupAck()",
        " received onCreatGroupAck status:$_status, state:$prevState>$state");
    return true;
  }

  bool onSubscribeAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;
    SubscriberInfo subscriberInfo = SubscriberInfo();
    subscriberInfo.fromJson(hyperCubeCommand.jsonData);

    if (!_status) {
      logger.add(EVENTTYPE.WARNING, "SignallingObject::onSubscribeAck()",
          " received onSubscribeAck FAIL status:$_status, state:$prevState>$state");
      state = SignallingObjectState.connected;
      onConnectionDataClosed();
      return true;
    }

    switch (state) {
      case SignallingObjectState.connected:
      case SignallingObjectState.closedForData:
        state = SignallingObjectState.subscribed;
        break;
      case SignallingObjectState.openForData:
        break;
      default:
        logger.add(EVENTTYPE.ERROR, "SignallingObject::onSubscribeAck()",
            " received subscriberAck in invalid state:$prevState>$state ");
        break;
    }
    return true;
  }

  bool onUnsubscribeAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;
    SubscriberInfo subscriberInfo = SubscriberInfo();
    subscriberInfo.fromJson(hyperCubeCommand.jsonData);
    String _groupName = subscriberInfo.groupName;
    state = SignallingObjectState.connected;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onSubscribeAck()",
        " received subscriberAck $_systemId group: $_groupName, status:$_status, state:$prevState>$state");
    //if (state != SignallingObjectState.closedForData) onConnectionDataClosed();
    return true;
  }

  bool onSubscriber(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool stat = hyperCubeCommand.status;
    SubscriberInfo subscriberInfo = SubscriberInfo();
    subscriberInfo.fromJson(hyperCubeCommand.jsonData);
    String _groupName = subscriberInfo.groupName;
    switch (state) {
      case SignallingObjectState.connected:
      case SignallingObjectState.subscribed:
      case SignallingObjectState.openForData:
      case SignallingObjectState.closedForData:
        state = SignallingObjectState.openForData;
        break;
      default:
        stat = false;
        logger.add(EVENTTYPE.ERROR, "SignallingObject::onSubscriber()",
            " received onSubscriber in invalid, state:$prevState>$state");
        break;
    }
    if (stat) onConnectionDataOpen(_groupName);
    return true;
  }

  bool onUnsubscriber(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    SubscriberInfo subscriberInfo = SubscriberInfo();
    subscriberInfo.fromJson(hyperCubeCommand.jsonData);
    String _groupName = subscriberInfo.groupName;

    logger.add(EVENTTYPE.INFO, "SignallingObject::onUnsubscriber()",
        " received subscriber $_systemId group: $_groupName, state:$prevState>$state");
    if (state != SignallingObjectState.closedForData) onConnectionDataClosed();
    return true;
  }

  bool onGetGroupsAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;
    GroupsInfoList getGroupsInfoList = GroupsInfoList();
    if (hyperCubeCommand.jsonData != null) {
      dynamic jgroupInfo = hyperCubeCommand.jsonData;
      getGroupsInfoList.fromJson(jgroupInfo);
    }
    List<GroupInfo> _groupInfoList = getGroupsInfoList.list;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onGetGroupsAck()",
        " received onGetGroupsAck status:$_status, items: ${_groupInfoList.length} state:$prevState>$state");
    hyperCubeClient.onGroupInfoList(_groupInfoList);
    //if (state != SignallingObjectState.closedForData) onConnectionDataClosed();
    return true;
  }

  bool onLogLinesAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;
    LineList lineList = LineList();
    if (hyperCubeCommand.jsonData != null) {
      dynamic jgroupInfo = hyperCubeCommand.jsonData;
      lineList.fromJson(jgroupInfo);
      hyperCubeClient.onLogLines(lineList);
    }
    logger.add(EVENTTYPE.INFO, "SignallingObject::onLogLinesAck()",
        " received onGetGroupsAck status:$_status, items: ${lineList.list.length} state:$prevState>$state");
    //hyperCubeClient.onLogLinesList(lineList);
    return true;
  }

  bool onStatusLinesAck(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    bool _status = hyperCubeCommand.status;
    LineList lineList = LineList();
    if (hyperCubeCommand.jsonData != null) {
      dynamic jgroupInfo = hyperCubeCommand.jsonData;
      lineList.fromJson(jgroupInfo);
      hyperCubeClient.onStatusLines(lineList);
    }
    logger.add(EVENTTYPE.INFO, "SignallingObject::onStatusLinesAck()",
        " received onGetGroupsAck status:$_status, items: ${lineList.list.length} state:$prevState>$state");
    //hyperCubeClient.onLogLinesList(lineList);
    return true;
  }

  bool onClosedForData(HyperCubeCommand hyperCubeCommand) {
    SignallingObjectState prevState = state;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onClosedForData()",
        " received $_systemId state:$prevState>$state");
    onConnectionDataClosed();
    return true;
  }

  bool onEchoData(HyperCubeCommand _hyperCubeCommand) {
    return sendSigCommand(
        _hyperCubeCommand.command, _hyperCubeCommand.jsonData, "onEchoData");
  }

  bool onRemotePing(HyperCubeCommand _hyperCubeCommand) {
    bool stat = true;
    String jsonString = _hyperCubeCommand.toString();
    if (_hyperCubeCommand.ack == true) {
      logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
          " received remotePing response $jsonString");
      logger.setStateInt(
          "HyperCubeClient-numRemotePingAcks", ++numRemotePingAcks);
    } else {
      logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
          " received remotePing request $jsonString");
      stat = sendSigCommand(
          _hyperCubeCommand.command, _hyperCubeCommand.jsonData, "onEchoData",
          ack: true);
      logger.setStateInt("HyperCubeClient-numRemotePings", ++numRemotePings);
    }
    return stat;
  }

  bool processMsgJson(String jsonString) {
    bool processed = false;
    HyperCubeCommand hyperCubeCommand =
        HyperCubeCommand(HYPERCUBECOMMANDS.NONE, null, true);
    try {
      hyperCubeCommand.fromJson(jsonDecode(jsonString));

      switch (hyperCubeCommand.command) {
        case HYPERCUBECOMMANDS.LOCALPING:
          logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
              " received localPing response $jsonString");
          processed = true;
          break;
        case HYPERCUBECOMMANDS.REMOTEPING:
          processed = onRemotePing(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.ECHODATA:
          processed = onEchoData(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.CONNECTIONINFOACK:
          processed = onConnectionInfoAck(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.CREATEGROUPACK:
          processed = onCreateGroupAck(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.SUBSCRIBER:
          processed = onSubscriber(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.UNSUBSCRIBER:
          processed = onUnsubscriber(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.SUBSCRIBEACK:
          processed = onSubscribeAck(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.UNSUBSCRIBEACK:
          processed = onUnsubscribeAck(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.GETGROUPSACK:
          processed = onGetGroupsAck(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.CLOSEDFORDATA:
          processed = onClosedForData(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.GETLOGLINESACK:
          processed = onLogLinesAck(hyperCubeCommand);
          break;
        case HYPERCUBECOMMANDS.GETSTATUSACK:
          processed = onStatusLinesAck(hyperCubeCommand);
          break;

        default:
      }
    } catch (e) {
      logger.add(EVENTTYPE.ERROR, "SignallingObject::processMsgJson()",
          jsonString + ", field not found " + e.toString());
    }
    return processed;
  }

  bool processMsg(MsgExt msgExt) {
    bool proceesed = false;
    SigMsg sigMsg = msgExt.getSigMsg();
    switch (sigMsg.subSys) {
      case SUBSYS_SIG:
        switch (sigMsg.command) {
          case SIG_JSON:
            proceesed = processMsgJson(sigMsg.jsonData);
            break;
          default:
        }
        break;
      default:
    }
    return proceesed;
  }

  bool processHostMsg(MsgExt msgExt) {
    return processMsg(msgExt);
  }

  onConnection() {
//    setSystemId(1231);
    sendConnectionInfo();
//    createGroup("vortexGroup");
//    subscribe("TeamPegasus");
//    localPing();
    //   subscribe("TeamPegasus");
    getGroups("Team");
  }

  onDisconnection() {
    state = SignallingObjectState.disconnected;
  }

  onConnectionDataOpen(String _groupName) {
    remotePing();
    hyperCubeClient.onConnectionDataOpen(_groupName);
    SignallingObjectState prevState = state;
    state = SignallingObjectState.openForData;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onConnectionDataOpen()",
        " state:$prevState>$state");
  }

  onConnectionDataClosed() {
    hyperCubeClient.onConnectionDataClosed();
    SignallingObjectState prevState = state;
    state = SignallingObjectState.closedForData;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onConnectionDataClosed()",
        " state:$prevState>$state");
  }

  bool sendSigCommand(
      HYPERCUBECOMMANDS command, dynamic data, String callingFunctionName,
      {status = true, ack = false}) {
    HyperCubeCommand hyperCubeCommand = HyperCubeCommand(command, data, status);
    hyperCubeCommand.ack = ack;
    String jsonString = jsonEncode(hyperCubeCommand.toJson());
    return sendSigMsg(jsonString, callingFunctionName, jsonString);
  }

  bool sendSigMsg(
      String jsonString, String callingFunctionName, String statusString) {
    SigMsg sigMsg = SigMsg(jsonString);
    bool stat = hyperCubeClient.sendMsg(sigMsg);

    if (stat)
      logger.add(
          EVENTTYPE.INFO, callingFunctionName, statusString + " succeded");
    else
      logger.add(
          EVENTTYPE.WARNING, callingFunctionName, statusString + " Failed");
    return stat;
  }

  bool sendConnectionInfo() {
    connectionInfo.serverIpAddress = hyperCubeClient.activeServerAddress.ip;
    return sendSigCommand(HYPERCUBECOMMANDS.CONNECTIONINFO, connectionInfo,
        "HyperCubeClient::SignallingObject()::sendConnectionInfo()");
  }

  bool createGroup(String groupName) {
    GroupInfo groupInfo = GroupInfo();
    groupInfo.groupName = groupName;
    return sendSigCommand(HYPERCUBECOMMANDS.CREATEGROUP, groupInfo,
        "HyperCubeClient::SignallingObject()::createGroup()");
  }

  bool localPing([bool ack = false, String pingData = "localPingFromVortex"]) {
    return sendSigCommand(HYPERCUBECOMMANDS.LOCALPING, pingData,
        "HyperCubeClient::SignallingObject()::localPing()");
  }

  bool remotePing(
      [bool ack = false, String pingData = "remotePingFromVortex"]) {
    return sendSigCommand(HYPERCUBECOMMANDS.REMOTEPING, pingData,
        "HyperCubeClient::SignallingObject()::remotePing()");
  }

  bool echoData([String echoData = "data12345"]) {
    return sendSigCommand(HYPERCUBECOMMANDS.ECHODATA, echoData,
        "HyperCubeClient::SignallingObject()::echoData()");
  }

  bool subscribe(String _groupName) {
    if ((state != SignallingObjectState.connected) &&
        (state != SignallingObjectState.closedForData)) return false;
    SubscriberInfo subscriberInfo = SubscriberInfo();
    subscriberInfo.groupName = _groupName;
    return sendSigCommand(HYPERCUBECOMMANDS.SUBSCRIBE, subscriberInfo,
        "HyperCubeClient::SignallingObject()::subscribe()");
  }

  bool unsubscribe(String _groupName) {
    SubscriberInfo subscriberInfo = SubscriberInfo();
    subscriberInfo.groupName = _groupName;
    return sendSigCommand(HYPERCUBECOMMANDS.UNSUBSCRIBE, subscriberInfo,
        "HyperCubeClient::SignallingObject()::unsubscribe()");
  }

  bool getGroups(String _searchWord, {startingIndex = 0, maxItems = 10}) {
    GetGroupsInfo getGroupsInfo = GetGroupsInfo();
    getGroupsInfo.searchWord = _searchWord;
    getGroupsInfo.startingIndex = startingIndex;
    getGroupsInfo.maxItems = maxItems;
    return sendSigCommand(HYPERCUBECOMMANDS.GETGROUPS, getGroupsInfo,
        "HyperCubeClient::SignallingObject()::getGroups()");
  }

  bool getLogLines(startingIndex, maxItems) {
    LineList lineList = LineList();
    lineList.startingIndex = startingIndex;
    lineList.numItems = maxItems;
    return sendSigCommand(HYPERCUBECOMMANDS.GETLOGLINES, lineList,
        "HyperCubeClient::SignallingObject()::getLogLines()");
  }

  bool getStatusLines(startingIndex, maxItems) {
    LineList lineList = LineList();
    lineList.startingIndex = startingIndex;
    lineList.numItems = maxItems;
    return sendSigCommand(HYPERCUBECOMMANDS.GETSTATUS, lineList,
        "HyperCubeClient::SignallingObject()::getStatusLines()");
  }
}
