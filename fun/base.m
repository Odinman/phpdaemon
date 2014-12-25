<?php
/*
  +----------------------------------------------------------------------+
  | Name:fun/base.m                                                      |
  +----------------------------------------------------------------------+
  | Comment:基础函数,函数名全部以_开头                                   |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2011-02-23 10:24:26                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2013-08-01 10:07:01                                    |
  +----------------------------------------------------------------------+
*/

/* {{{ 精确时间
 */
function _microtimeFloat() {
    list($usec,$sec)=explode(" ",microtime());
    return ((float)$usec+(float)$sec);
}
/* }}} */

/* {{{ 程序速度
 */
function _procSpeed() {
    $cur_stamp=_microtimeFloat();
    $GLOBALS['requestDuration']=round($cur_stamp-$GLOBALS['firstStamp'],6);
    $GLOBALS['requestTip']=round($cur_stamp-$GLOBALS['lastStamp'],6);
    $GLOBALS['lastStamp']=$cur_stamp;
    return "{$GLOBALS['requestTip']}/{$GLOBALS['requestDuration']}";
}
/* }}} */

/* {{{ _traceSpeed
 */
function _traceSpeed($tag) {
    $cur_stamp=_microtimeFloat();
    if (!isset($GLOBALS['_TRACESPEED_'][$tag])) {    //测速开始
        $GLOBALS['_TRACESPEED_'][$tag]=$cur_stamp;
        _debug("[".__FUNCTION__."][{$tag}][trace_begin]",_DLV_CRIT);
    } else {    //测速结束
        $dura=round(($cur_stamp-$GLOBALS['_TRACESPEED_'][$tag])*1000,3);
        _debug("[".__FUNCTION__."][{$tag}][dura:{$dura}ms][trace_end]",_DLV_CRIT);
        unset($GLOBALS['_TRACESPEED_'][$tag]);
    }
    return true;
}
/* }}} */

/* {{{ 读取命令行参数
 */
function _readArgv($argvTag='@') {
    $ret=false;
    $orig_argv=$GLOBALS['argv'];
    if (!empty($orig_argv) && is_array($orig_argv)) {
        $offset=1;  //0忽略
        foreach ($orig_argv as $key=>$argv_value) {
            if ($key==$offset) {
                if ($argv_value[0]==$argvTag) {  // 以'-'开头的,这个后面需要跟具体值
                    $key=substr($argv_value,1);
                    $next_value=$orig_argv[++$offset];
                    if (null!==($next_value) && $next_value[0]!=$argvTag) {
                        $ret[$key]=$next_value;
                    } else {
                        $ret[$key]=true;
                        --$offset;
                    }
                } else {
                    $ret[$argv_value]=true;
                }
                $offset++;
            }
        }
    }

    return $ret;
}
/* }}} */

/* {{{ netRnage
 * network mask
 */
function _netRange($IP,$mask=24) {
    $classclong=ip2long($IP)&~((1<<(32-$mask))-1);
    return long2ip($classclong);
}
/* }}} */

/* {{{ _sleep
 * 循环函数, 代替以前简单的sleep, 支持小数点
 */
function _sleep($sleepSeconds = 0) {
    if ($sleepSeconds !== 0) {
        usleep($sleepSeconds*1000000);
    }

    return true;
}
/* }}} */

/* {{{ _createGuid
 */
function _createGuid($namespace = '') {
    static $guid = '';
    $uid = uniqid("", true);
    $data = $namespace;
    $data .= $_SERVER['REQUEST_TIME'];
    $data .= $_SERVER['HOSTNAME'];
    $hash = strtolower(hash('ripemd128', $uid . $guid . md5($data)));
    $guid = substr($hash,  0,  8) .
        '-' .
        substr($hash,  8,  4) .
        '-' .
        substr($hash, 12,  4) .
        '-' .
        substr($hash, 16,  4) .
        '-' .
        substr($hash, 20, 12);
    return $guid;
}
/* }}} */

/* {{{ 截取
 */
function _numberFormat($number, $decimals='', $sep1='.', $sep2='') {
    if (($number * pow(10 , $decimals + 1) % 10 ) == 5)  //if next not significant digit is 5
        $number -= pow(10 , -($decimals+1));
    return number_format($number, $decimals, $sep1, $sep2);
}
/* }}} */
