<?php
/*
  +----------------------------------------------------------------------+
  | Name: omq.m                                                          |
  +----------------------------------------------------------------------+
  | Comment:                                                             |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2015-04-09 22:28:38                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2015-04-09 22:28:58                                    |
  +----------------------------------------------------------------------+
*/

/* {{{ function _getOmqPoller($host,$port)
 *
 */
function _getOmqPoller($host,$port) {
    //$name=substr(_shortenUUID(_createUUID()),0,10);
    //$queue = new ZMQSocket(new ZMQContext(), ZMQ::SOCKET_REQ, $name);
    $queue = new ZMQSocket(new ZMQContext(), ZMQ::SOCKET_REQ);
    //$queue->disconnect("tcp://{$host}:{$port}");
    $queue->connect("tcp://{$host}:{$port}");
    $queue->setSockOpt (ZMQ::SOCKOPT_LINGER, 1000);
    $poller = new ZMQPoll();
    $poller->add($queue, ZMQ::POLL_IN | ZMQ::POLL_OUT);
    return $poller;
}
/* }}} */

/* {{{ function _omqPollDo($poller,$msg, $timeout=0)
 *
 */
function _omqPollDo($poller,$msg, $timeout=0) {
    $rt=false;

    if ($timeout>0) {
        $to=($timeout+1)*1000;
    } else {
        $to=3000;
    }
    do {
        $senders = array();
        $receivers= array();
        $poller->poll($receivers, $senders, $to);

        if (count($senders)>0) {
            $sender=$senders[0];
            $sender->sendmulti($msg, ZMQ::MODE_DONTWAIT);
        } else {
            break;
        }

        $poller->poll($receivers, $senders, $to);

        if (count($receivers)>0) {
            $receiver=$receivers[0];
            $tmp = $receiver->recvMulti();
        } else {
            break;
        }

        if (!$tmp) {
            break;
        }

        $r = array_shift($tmp);
        if ($r == "NIL") {
            $rt = NULL;
            break;
        } elseif ($r != "OK") {
            break;
        }

        if (empty($tmp)) {  //仅仅返回OK,代表成功
            $rt=true;
        } else {
            $rt=$tmp;
        }
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _omqPollPush()
 *
 */
function _omqPollPush() {
    $args=func_get_args();
    $poller=array_shift($args);  //第一个参数是queue,取出
    array_unshift($args, "PUSH");    //放命令到数组头部
    //return _omqDo($poller,array("PUSH",$key,$value));
    return _omqPollDo($poller,$args);
}
/* }}} */

/* {{{ function _omqPollPop($poller,$key, $timeout=0)
 * timeout大于0是为阻塞式
 */
function _omqPollPop($poller,$key,$timeout=0) {
    $rt=false;

    $to=$timeout*1000;
    $start=_microtimeFloat();
    $tried=0;
    do {
        $tried++;
        $rt=_omqPollDo($poller,array("POP",$key));

        $end=_microtimeFloat();

        $dura=round(($end-$start)*1000,3);

        $i=10000;
        if ($dura<$to && $rt===NULL) {
            $sl=$i*(1<<$tried)>=500000?500000:$i*(1<<$tried);
            usleep($sl);
        } else {
            //不阻塞，直接返回
            //_notice("[%s][tried: %d][to: %d][dura: %d]",__FUNCTION__,$tried,$to,$dura);
            break;
        }
    } while($rt===NULL);
    //_notice("[%s][tried: %d]",__FUNCTION__,$tried);

    return $rt;
}
/* }}} */

/* {{{ function _omqPollBPop($poller,$key, $timeout=0)
 * timeout大于0是为阻塞式
 */
function _omqPollBPop($poller,$key,$timeout=0) {
    $rt=false;

    $to=$timeout*1000;
    $start=_microtimeFloat();
    $tried=0;
    do {
        $tried++;
        $rt=_omqPollDo($poller,array("BPOP",$key, $timeout),$timeout);

        $end=_microtimeFloat();

        $dura=round(($end-$start)*1000,3);

        $i=10000;
        if ($dura<$to && $rt===NULL) {
            $sl=$i*(1<<$tried)>=500000?500000:$i*(1<<$tried);
            usleep($sl);
        } else {
            //不阻塞，直接返回
            //_notice("[%s][tried: %d][to: %d][dura: %d]",__FUNCTION__,$tried,$to,$dura);
            break;
        }
    } while($rt===NULL);
    //_notice("[%s][tried: %d]",__FUNCTION__,$tried);

    return $rt;
}
/* }}} */

/* {{{ function _omqPollGet($poller,$key, $timeout=0)
 *
 */
function _omqPollGet($poller,$key,$timeout=0) {
    return _omqPollDo($poller,array("GET","",$key),$timeout);
}
/* }}} */

/* {{{ function _omqPollDel($poller,$key)
 *
 */
function _omqPollDel($poller,$key) {
    return _omqPollDo($poller,array("DEL","",$key));
}
/* }}} */

/* {{{ function _omqPollSet($poller,$key, $value)
 *
 */
function _omqPollSet($poller,$key,$value) {
    //return _omqPollDo($poller,array("SET","",$key,$value));
    $args=func_get_args();
    $poller=array_shift($args);  //第一个参数是queue,取出
    array_unshift($args, "SET", "");    //放命令到数组头部
    return _omqPollDo($poller,$args);
}
/* }}} */

/* {{{ function _omqPollComplete($poller,$key, $value)
 *
 */
function _omqPollComplete($poller,$key,$value) {
    //return _omqPollDo($poller,array("SET","",$key,$value));
    $args=func_get_args();
    $poller=array_shift($args);  //第一个参数是queue,取出
    array_unshift($args, "COMPLETE", "");    //放命令到数组头部
    return _omqPollDo($poller,$args);
}
/* }}} */

