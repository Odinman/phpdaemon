<?php
/*
  +----------------------------------------------------------------------+
  | Name: main.m                                                         |
  +----------------------------------------------------------------------+
  | Comment: 主程序                                                      |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-05-09 23:20:45                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2013-07-29 22:15:08                                    |
  +----------------------------------------------------------------------+
*/
error_reporting(0);

define('_DAEMON_ROOT', dirname(__FILE__).'/');

//const
include_once(_DAEMON_ROOT.'inc/const.m');

//functions
include_once(_DAEMON_ROOT.'fun/base.m');
include_once(_DAEMON_ROOT.'fun/daemon.m');
include_once(_DAEMON_ROOT.'fun/file.m');
include_once(_DAEMON_ROOT.'fun/ip.m');

/* {{{ 初始化(读取配置项等)
 */
include_once(_DAEMON_ROOT.'modules/initDaemon.m');
/* }}} */

// Daemonize
include_once(_DAEMON_ROOT.'modules/daemonize.m');

/* {{{ 这时确定model
 */
if (isset($GLOBALS['DATA'])) {  //如果没有配置数据层,可以不连
    include_once(_DAEMON_ROOT._SUBDIR_DATA.'/IData.m');
    include_once($GLOBALS['DATA']['file']);
}
/* }}} */

/* {{{ 后加载,加入worker定义初始化信息
 * 这些文件需要放在worker目录下,并且以path=file形式出现,如果一个目录下有多个文件,用','分隔
 */
if (!empty($GLOBALS['OPTIONS']['postload'])) {
    foreach ($GLOBALS['OPTIONS']['postload'] as $postPath=>$postBases) {
        $bases=explode(',',$postBases);
        foreach ($bases as $base) {
            $postFile=$GLOBALS['_daemon']['_WORKERROOT_'].'/'.$postPath.'/'.$base;
            if (@include_once($postFile)) {
                _debug("[post:$postFile][loaded]",_DLV_NOTICE);
            } else {
                _debug("[post:$postFile][load_fail]",_DLV_NOTICE);
            }
        }
    }
}
/* }}} */

$loop=0;
while($GLOBALS['_daemon']['masterRun']===true) {
    $loop++;
    // In a real world scenario we would do some sort of conditional launch.
    // Maybe a condition in a DB is met, or whatever, here we're going to
    // cap the number of concurrent grandchildren
    $workerRun=false;
    foreach ($GLOBALS['_daemon']['runningWorkers'] as $workerTitle=>$workerStatus) {
        if ($workerStatus['wcount']>0) {
            //可能一个脚本需要fork多个worker
            for ($wSN=1;$wSN<=$workerStatus['wcount'];$wSN++) {
                if ($workerStatus["#{$wSN}"]['stat']===_PSTAT_STANDBY) {    //说明这个worker等着被启动...
                    $workerRun=true;    //只要有一个worker还在跑,就标记workerRun为true
                    //spawn worker
                    _debug("[{$workerStatus["#{$wSN}"]['title']}][spawn_it]",_DLV_NOTICE);
                    $wPid=_spawnWorker($workerStatus["#{$wSN}"]);
                    if (-1 === $wPid) {
                        _debug("[{$workerTitle}][#{$wSN}][spawn_failed]",_DLV_EMERG);
                    } else {
                        _debug("[{$workerTitle}][#{$wSN}][pid:$wPid][spawn_successful]",_DLV_WARNING);
                        $GLOBALS['_daemon']['runningWorkers'][$workerTitle]["#{$wSN}"]['stat']=_PSTAT_RUNNING;
                        $GLOBALS['_daemon']['runningWorkers'][$workerTitle]["#{$wSN}"]['pid']=$wPid;
                        $GLOBALS['_daemon']['runningWorkers']['_pids'][$wPid]="{$workerTitle}#{$wSN}";
                    }
                } elseif ($workerStatus["#{$wSN}"]['stat']===_PSTAT_RUNNING) {
                    $workerRun=true;
                }
            }
        }
    }

    _iterate(0.5);

    pcntl_signal_dispatch();

    if ($workerRun===false) {   //没有worker在运行了,完成历史使命,退出
    //if ($GLOBALS['OPTIONS']['mode']==='run') {
        _debug("[no_worker_running]",_DLV_CRIT);
        $GLOBALS['_daemon']['masterRun']=false;
    }
    // show status, once per 500
    if ($loop%500==0) {
        $pidArr=array();
        $titleArr=array();
        foreach ($GLOBALS['_daemon']['runningWorkers'] as $key=>$value) {
            if ($key=='_pids') {
                foreach ($value as $workerPid=>$workerInfo) {
                    $pidArr[]="{$workerPid}:{$workerInfo}";
                }
                $pidStr=implode(',',$pidArr);
            } else {
                $wTitle=$key;
                foreach ($value as $snStr=>$snDetail) {
                    $titleArr[]="{$wTitle}:{$snStr}:{$snDetail['pid']}:{$snDetail['stat']}";
                }
            }
        }
        $titleStr=implode(',',$titleArr);
        _debug("[{$pidStr}][{$titleStr}]",_DLV_CRIT);
    }
}

_shutdown(0);
