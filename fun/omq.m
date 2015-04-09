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

/* {{{ function _connectOMQ($host,$port)
 *
 */
function _connectOMQ($host,$port) {
    $queue = new ZMQSocket(new ZMQContext(), ZMQ::SOCKET_REQ, "MySock1");
    $queue->connect("tcp://{$host}:{$port}");
    return $queue;
}
/* }}} */

/* {{{ function _omqDo($queue,$msg)
 *
 */
function _omqDo($queue,$msg) {
    $rt = false;

    do {
        $tmp=$queue->sendmulti($msg)->recvMulti();

        $r = array_shift($tmp);
        if ($r == "NIL") {
            $rt = NULL;
            break;
        } elseif ($r != "OK") {
            break;
        }

        $rt=$tmp;

    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _omqPush($queue,$key, $value)
 *
 */
function _omqPush($queue,$key,$value) {
    return _omqDo($queue,array("PUSH","",$key,$value));
}
/* }}} */

/* {{{ function _omqPop($queue,$key)
 *
 */
function _omqPop($queue,$key) {
    return _omqDo($queue,array("POP",$key));
}
/* }}} */

/* {{{ function _omqGet($queue,$key)
 *
 */
function _omqGet($queue,$key) {
    return _omqDo($queue,array("GET","",$key));
}
/* }}} */

/* {{{ function _omqDel($queue,$key)
 *
 */
function _omqDel($queue,$key) {
    return _omqDo($queue,array("DEL","",$key));
}
/* }}} */

/* {{{ function _omqSet($queue,$key, $value)
 *
 */
function _omqSet($queue,$key,$value) {
    return _omqDo($queue,array("SET","",$key,$value));
}
/* }}} */

