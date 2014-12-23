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

/* {{{ debug 错误级别
 */
define('_DLV_INFO',    1);
define('_DLV_NOTICE',  2);
define('_DLV_WARNING', 3);
define('_DLV_ERROR',   4);
define('_DLV_CRIT',    5);
define('_DLV_ALERT',   6);
define('_DLV_EMERG',   7);
define('_DLV_NONE',    8);
/* }}} */

/* {{{ syslog
 */
//facility
define('_FACILITY_AUTH',     LOG_AUTH);
define('_FACILITY_AUTHPRIV', LOG_AUTHPRIV);
define('_FACILITY_CRON',     LOG_CRON);
define('_FACILITY_DAEMON',   LOG_DAEMON);
define('_FACILITY_KERN',     LOG_KERN);
define('_FACILITY_LOCAL0',   LOG_LOCAL0);
define('_FACILITY_LOCAL1',   LOG_LOCAL1);
define('_FACILITY_LOCAL2',   LOG_LOCAL2);
define('_FACILITY_LOCAL3',   LOG_LOCAL3);
define('_FACILITY_LOCAL4',   LOG_LOCAL4);
define('_FACILITY_LOCAL5',   LOG_LOCAL5);
define('_FACILITY_LOCAL6',   LOG_LOCAL6);
define('_FACILITY_LOCAL7',   LOG_LOCAL7);
define('_FACILITY_LPR',      LOG_LPR);
define('_FACILITY_MAIL',     LOG_MAIL);
define('_FACILITY_NEWS',     LOG_NEWS);
define('_FACILITY_SYSLOG',   LOG_SYSLOG);
define('_FACILITY_USER',     LOG_USER);
define('_FACILITY_UUCP',     LOG_UUCP);
define('_FACILITY_DEFAULT',  LOG_LOCAL3);
//priority
define('_PRIORITY_EMERG',    LOG_EMERG);
define('_PRIORITY_ALERT',    LOG_ALERT);
define('_PRIORITY_CRIT',     LOG_CRIT);
define('_PRIORITY_ERR',      LOG_ERR);
define('_PRIORITY_WARNING',  LOG_WARNING);
define('_PRIORITY_NOTICE',   LOG_NOTICE);
define('_PRIORITY_INFO',     LOG_INFO);
define('_PRIORITY_DEBUG',    LOG_DEBUG);
define('_PRIORITY_DEFAULT',  LOG_DEBUG);
/* }}} */

/* {{{ 获取debug级别
 * @param string $lvStr debug字符串
 */
function _getDebugLevel($lvStr='') {
    if (is_numeric($lvStr)) {   //是数字直接返回数字
        return (int)$lvStr;
    } elseif ($lv=constant('_DLV_'.strtoupper($lvStr))) {
        return $lv;
    } else {
        return _DLV_NONE;
    }
}
/* }}} */

/* {{{ 日志注册器
 * 将日志配置存入$GLOBALS['sysLog']中,可按照需要增加键指,默认_debug不能占用
 */
function _syslogRegister($logSettingStr=null,$logRKey=null,$logTag=null) {
    $logRKey=empty($logRKey)?'_debug':$logRKey; //下划线开头,避免冲突
    $GLOBALS['sysLog'][$logRKey]['tag']=empty($logTag)?'mDaemon':$logTag;

    list($facStr,$priStr)=explode('.',$logSettingStr);

    if ($facility=constant('_FACILITY_'.strtoupper($facStr))) {
        $GLOBALS['sysLog'][$logRKey]['facility']=$facility;
    } else {
        $GLOBALS['sysLog'][$logRKey]['facility']=_FACILITY_DEFAULT;
    }
    if ($priority=constant('_PRIORITY_'.strtoupper($priStr))) {
        $GLOBALS['sysLog'][$logRKey]['priority']=$priority;
    } else {
        $GLOBALS['sysLog'][$logRKey]['priority']=_PRIORITY_DEFAULT;
    }

    return true;
}
_syslogRegister();  //默认配置
/* }}} */

/* {{{ debug描述
 * @param $lv int debug级别
 */
function _getDebugDesc($lv) {
    switch($lv) {
    case _DLV_INFO:
        $ret='INFO';
        break;
    case _DLV_NOTICE:
        $ret='NOTICE';
        break;
    case _DLV_WARNING:
        $ret='WARNING';
        break;
    case _DLV_ERROR:
        $ret='ERROR';
        break;
    case _DLV_CRIT:
        $ret='CRIT';
        break;
    case _DLV_ALERT:
        $ret='ALERT';
        break;
    case _DLV_EMERG:
        $ret='EMERG';
        break;
    case _DLV_NONE:
    default:
        $ret='NONE';
        break;
    }
    return $ret;
}
/* }}} */

/* {{{ 记录系统日志
 * @param   string  $data       log内容
 * @param   string  $tag        log标识
 * @param   int     $facility   log分类(与/etc/syslog.conf对应)
 * @param   int     $priority   log级别(与/etc/syslog.conf对应)  
 *
 * @return  null
 */
function _saveSysLog($data,$logRKey) {
    do {
        if (empty($data)) {
            _debug("[".__FUNCTION__."][no_data]",_DLV_CRIT,false);
            break;
        }
        if (false==($logSetting=$GLOBALS['sysLog'][$logRKey])) {
            _debug("[".__FUNCTION__."][logsetting_invalid]",_DLV_CRIT,false);
            break;
        }
        if (empty($logSetting['tag']) || empty($logSetting['facility']) || empty($logSetting['priority'])) {
            _debug("[".__FUNCTION__."][logsetting_miss]",_DLV_CRIT,false);
            break;
        }
        openlog($logSetting['tag'],LOG_PID,$logSetting['facility']);
        syslog($logSetting['priority'],$data);
        closelog();
    } while(false);
}
/* }}} */

/* {{{ debug函数
 * @param   string  $debugData      debug内容
 * @param   int     $debugLevel     debug级别
 *
 * @return  null
 */
$GLOBALS['OPTIONS']['debug_level']=_DLV_NOTICE;   //未初始化之前,显示NOTICE以上的debug信息
function _debug($debugData,$debugLevel=_DLV_INFO,$sysLog=true) {
    if ($debugLevel>=$GLOBALS['OPTIONS']['debug_level'] && !empty($debugData)) {
        $lvDesc=_getDebugDesc($debugLevel);
        /* {{{ data prefix
         */
        $dataPrefix="[{$GLOBALS['_daemon']['role']}]";
        if (!empty($GLOBALS['_daemon']['title'])) {
            $dataPrefix.="[{$GLOBALS['_daemon']['title']}]";
        }
        if (!empty($dataPrefix)) {
            $dataPrefix.=' ';
        }

        $dataSuffix=' ';
        if (!empty($GLOBALS['moduleName'])) {
            $dataSuffix.="[{$GLOBALS['moduleName']}]";
        }
        $dataSuffix.="["._procSpeed()."][$lvDesc]";

        $debugData=$dataPrefix.$debugData.$dataSuffix;
        /* }}} */
        if ($GLOBALS['OPTIONS']['show_debug']) {
            printf("[%s]%s\n",date('Y-m-d H:i:s'),$debugData);
        }
        if ($sysLog===true) {
            if (isset($GLOBALS['sysLog']['_debug'])) {
                _saveSysLog($debugData,'_debug');
            } else {
                //还没有register,直接output
                printf("[%s]%s\n",date('Y-m-d H:i:s'),$debugData);
            }
        }
    }
}
/* }}} */

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
