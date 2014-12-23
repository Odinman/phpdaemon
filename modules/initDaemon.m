<?php
/*
  +----------------------------------------------------------------------+
  | Name: modules/initDaemon.m                                           |
  +----------------------------------------------------------------------+
  | Comment: 初始化                                                      |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-05-13 11:29:08                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2013-07-29 23:15:38                                    |
  +----------------------------------------------------------------------+
*/
$moduleName=basename(__FILE__);

// Garbage Collection (PHP >= 5.3)
if (function_exists('gc_enable')) {
    gc_enable();
}

/* {{{ timezone
 *  */
$tzStr=empty($_SERVER['timezone'])?'Asia/Shanghai':$_SERVER['timezone'];
date_default_timezone_set($tzStr);
/* }}} */

/* {{{ 初始化全局变量
 */
$GLOBALS['OPTIONS']=array();
//角色
$GLOBALS['_daemon']['role']='father';   //default master
//状态
$GLOBALS['_daemon']['status']='foreground'; //状态,前台或者后台,foreground/background
$GLOBALS['_daemon']['count']=0;
//time info
list($usec,$GLOBALS['currentTime'])=explode(" ",microtime());
$GLOBALS['firstStamp']=(float)$usec+(float)$GLOBALS['currentTime'];    //请求开始时间
$GLOBALS['lastStamp']=$GLOBALS['firstStamp'];
$GLOBALS['requestDuration']=0;
/* }}} */

/* {{{ command line params
 * 注意这些参数默认是以'@'开头的,以避免跟hphp等冲突
 */
$GLOBALS['PARAMS']=_readArgv();
/* }}} */

/* {{{ daemon run time options
 * 这里定义最基础的配置项目,全部要在hiphop配置文件中定义,并且都有默认值
 * 约定所有在hiphop中定义的配置都小写字母,并且用下划线'_'分隔
 * 如果不是hiphop, 环境变量也会到$_SERVER数组中去,(启动脚本可以支持这种配置)
 * 如果有额外需要定义的配置,也在这里指定(文件)
 */
//自定义的配置文档, 必须为ini格式
$GLOBALS['configFile']=empty($GLOBALS['PARAMS']['c'])?(isset($_SERVER['config_file'])?$_SERVER['config_file']:''):$GLOBALS['PARAMS']['c'];
//程序设置(综合参数以及配置文件,支持多次load,这之前的设置都是不能reload)
_loadOptions();

// 不可reload的程序配置, 配置项与数组键值不能相同
// 运行模式 daemon|run
if (isset($GLOBALS['PARAMS']['m'])) {
    $GLOBALS['OPTIONS']['mode']=$GLOBALS['PARAMS']['m'];
} elseif ($GLOBALS['PARAMS']['mode']) {
    $GLOBALS['OPTIONS']['mode']=$GLOBALS['PARAMS']['mode'];
} elseif (isset($GLOBALS['OPTIONS']['daemon_mode'])) {  //这个key必须不一样,否则会被reload
    $GLOBALS['OPTIONS']['mode']=$GLOBALS['OPTIONS']['daemon_mode'];
}
//进程title,关系到pid,状态文件的名称
if (isset($GLOBALS['PARAMS']['t']) || isset($GLOBALS['PARAMS']['title'])) {
    $GLOBALS['OPTIONS']['title']=isset($GLOBALS['PARAMS']['t'])?$GLOBALS['PARAMS']['t']:$GLOBALS['PARAMS']['title'];
} elseif (isset($GLOBALS['OPTIONS']['daemon_title'])) {
    $GLOBALS['OPTIONS']['title']=$GLOBALS['OPTIONS']['daemon_title'];
}

/* {{{ load 3part lib
 */
if ($GLOBALS['OPTIONS']['libs']['redis']==='1' || strtolower($GLOBALS['OPTIONS']['libs']['redis'])==='yes') {
    include_once(_DAEMON_ROOT.'lib/Predis.php');
}
if ($GLOBALS['OPTIONS']['libs']['thrift']==='1' || strtolower($GLOBALS['OPTIONS']['libs']['thrift'])==='yes') {
	$GLOBALS['THRIFT_ROOT'] = _DAEMON_ROOT . 'lib/thrift';
	require_once($GLOBALS['THRIFT_ROOT'] . '/Thrift.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/transport/TSocket.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/transport/TBufferedTransport.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/protocol/TBinaryProtocol.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/transport/TFramedTransport.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/packages/Hbase/Hbase.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/packages/hadoopfs/ThriftHadoopFileSystem.php');
	require_once($GLOBALS['THRIFT_ROOT'] . '/packages/scribe/scribe.php');
}
/* }}} */


/* {{{ workers
 */
$GLOBALS['_daemon']['_WORKERROOT_']=empty($GLOBALS['OPTIONS']['worker_root'])?(empty($_SERVER['WORKERROOT'])?_DAEMON_ROOT._SUBDIR_WORKERS:$_SERVER['WORKERROOT']):empty($GLOBALS['OPTIONS']['worker_root']);  //默认是_DAEMON_ROOT._SUBDIR_WORKERS
if (!empty($GLOBALS['OPTIONS']['workers'])) {
    foreach ($GLOBALS['OPTIONS']['workers'] as $workerTitle=>$workerInfo) {
        list($scriptFile,$workerCount,$maxLoop)=explode('*',$workerInfo);   //脚本名, worker数, 最大轮询数(处理几次结束)
        $workerCount=((int)$workerCount===0)?1:(int)$workerCount;
        $maxLoop=((int)$maxLoop===0)?1:(int)$maxLoop;  //默认1次
        if (!empty($workerTitle) && empty($GLOBALS['OPTIONS']['title'])) {  //如果没有定义daemon_title, 则用第一个
            $GLOBALS['OPTIONS']['title']=$workerTitle;
        }
        $workScript=$GLOBALS['_daemon']['_WORKERROOT_'].'/'.$scriptFile;
        $GLOBALS['_daemon']['runningWorkers'][$workerTitle]=array(
            'script' => $workScript,
            'wcount' => $workerCount,
        );
        for($i=1;$i<=$workerCount;$i++) {
            $GLOBALS['_daemon']['runningWorkers'][$workerTitle]["#{$i}"]=array(
                'realTitle' => $workerTitle,
                'title' => "{$workerTitle}#{$i}",
                'max' => $maxLoop,
                'sn' => $i,
                'script' => $workScript,
                'pid' => 0, //spawn成功后改变
                'stat' => _PSTAT_STANDBY,
            );
        }
    }
}
/* }}} */


if (empty($GLOBALS['OPTIONS']['title'])) {  // 必须要有
     debug("Not Found Process Title",_DLV_EMERG);
    _shutdown();
}
/* }}} */

/* {{{ 预加载,加入worker定义的一些常数以及函数(php文件)
 * 这些文件需要放在worker目录下,并且以path=file形式出现,如果一个目录下有多个文件,用','分隔
 */
if (!empty($GLOBALS['OPTIONS']['preload'])) {
    foreach ($GLOBALS['OPTIONS']['preload'] as $prePath=>$preBases) {
        $bases=explode(',',$preBases);
        foreach ($bases as $base) {
            $preFile=$GLOBALS['_daemon']['_WORKERROOT_'].'/'.$prePath.'/'.$base;
            if (@include_once($preFile)) {
                _debug("[pre:{$preFile}][loaded]",_DLV_NOTICE);
            } else {
                _debug("[pre:{$preFile}][load_fail]",_DLV_NOTICE);
            }
        }
    }
}
/* }}} */

/* {{{ runtime 
 */
// 注册debug的syslog信息,$GLOBALS['sysLog']['_debug'],reload无效
_syslogRegister($GLOBALS['OPTIONS']['debug_log'],'_debug',$GLOBALS['OPTIONS']['title']);

//run files
$GLOBALS['_daemon']['_RUNROOT_']=empty($GLOBALS['OPTIONS']['run_root'])?(empty($_SERVER['RUNROOT'])?_DAEMON_ROOT._SUBPATH_RUN:$_SERVER['RUNROOT']):empty($GLOBALS['OPTIONS']['run_root']);  //默认是_DAEMON_ROOT._SUBDIR_WORKERS
$GLOBALS['_daemon']['pidFile']=$GLOBALS['_daemon']['_RUNROOT_'].'/'.$GLOBALS['OPTIONS']['title'].'.pid';
_makeDir($GLOBALS['_daemon']['pidFile'],"0755",0,'f');
$GLOBALS['_daemon']['statusFile']=$GLOBALS['_daemon']['_RUNROOT_'].'/'.$GLOBALS['OPTIONS']['title'].'.status';
_makeDir($GLOBALS['_daemon']['statusFile'],"0755",0,'f');

//tmp dir
$GLOBALS['_daemon']['tmpDir']=$GLOBALS['_daemon']['_WORKERROOT_'].'/'._SUBPATH_TMP;
_makeDir($GLOBALS['_daemon']['tmpDir'],"0755",0,'d');
/* }}} */

unset($moduleName);
