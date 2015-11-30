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
    $queue->setSockOpt (ZMQ::SOCKOPT_LINGER, 1000);
    return $queue;
}
/* }}} */

/* {{{ function _omqDo($queue,$msg)
 *
 */
function _omqDo($queue,$msg) {
    $rt = false;

    do {
        $send_retries = 3;
        $sent    = false;
        $receive_retries = 3;
        $received  = false;
        // sending
        while(!$sent || $send_retries--) {
            try {
                if ($queue->sendmulti($msg, ZMQ::MODE_DONTWAIT) !== false) {
                    $sent=true;
                }
            } catch (ZMQSocketException $e) {
                //_notice("[%s]get error: %s",__FUNCTION__, $e->getMessage());
            }
            usleep(1000);
        }

        if (!$sent) {
            break;
        }

        while(!$received || $receive_retries--) {
            try {
                $tmp = $queue->recvMulti(ZMQ::MODE_DONTWAIT);
                if ($tmp) {
                    $received = true;
                }
            } catch (ZMQSocketException $e) {
                //_notice("[%s]get error: %s",__FUNCTION__, $e->getMessage());
            }
            //echo "sleep\n";
            usleep(1000);
        }

        if (!$received) {
            break;
        }

        print_r($tmp);
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

/* {{{ function _omqBTask()
 *
 */
//function _omqBTask($queue,$key,$value) {
function _omqBTask() {
    $args=func_get_args();
    $queue=array_shift($args);  //第一个参数是queue,取出
    array_unshift($args, "BTASK");    //放命令到数组头部
    //return _omqDo($queue,array("PUSH",$key,$value));
    return _omqDo($queue,$args);
}
/* }}} */

/* {{{ function _omqPush()
 *
 */
//function _omqPush($queue,$key,$value) {
function _omqPush() {
    $args=func_get_args();
    $queue=array_shift($args);  //第一个参数是queue,取出
    array_unshift($args, "PUSH");    //放命令到数组头部
    //return _omqDo($queue,array("PUSH",$key,$value));
    return _omqDo($queue,$args);
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
    //return _omqDo($queue,array("SET","",$key,$value));
    $args=func_get_args();
    $queue=array_shift($args);  //第一个参数是queue,取出
    array_unshift($args, "SET");    //放命令到数组头部
    return _omqDo($queue,$args);
}
/* }}} */

