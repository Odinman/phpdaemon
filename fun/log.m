<?php
/*
  +----------------------------------------------------------------------+
  | Name: fun/log.m                                                      |
  +----------------------------------------------------------------------+
  | Comment: 日志函数                                                    |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created: 2014-12-25 01:58:11                                         |
  +----------------------------------------------------------------------+
  | Last-Modified: 2014-12-25 01:57:59                                   |
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

// format形式的debug日志记录

/* {{{ function _info() {
 * 记录info级别的日志
 */
function _info() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_INFO);
}
/* }}} */

/* {{{ function _notice() {
 * 记录notice级别的日志
 */
function _notice() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_NOTICE);
}
/* }}} */

/* {{{ function _warn() {
 * 记录warn级别的日志
 */
function _warn() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_WARNING);
}
/* }}} */

/* {{{ function _error() {
 * 记录error级别的日志
 */
function _error() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_ERROR);
}
/* }}} */

/* {{{ function _crit() {
 * 记录crit级别的日志
 */
function _crit() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_CRIT);
}
/* }}} */

/* {{{ function _alert() {
 * 记录alert级别的日志
 */
function _alert() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_ALERT);
}
/* }}} */

/* {{{ function _emerg() {
 * 记录emerg级别的日志
 */
function _emerg() {
    $data = call_user_func_array("sprintf",func_get_args());
    _debug($data, _DLV_EMERG);
}
/* }}} */
