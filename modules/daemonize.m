<?php
/*
  +----------------------------------------------------------------------+
  | Name: modules/daemonize.m                                            |
  +----------------------------------------------------------------------+
  | Comment: daemonize                                                   |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-06-27 10:48:10                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2012-09-17 00:48:25                                    |
  +----------------------------------------------------------------------+
*/
$moduleName=basename(__FILE__);

_debug("[{$GLOBALS['OPTIONS']['title']}][forking]");
if (function_exists('pcntl_fork')) {
$pid = pcntl_fork(); // parent gets the child PID, child gets 0
} else {
    echo "can not fork!\n";
}
_debug("[{$pid}][forked]");
if ($pid === -1) {
    _debug('Process could not be forked');
    _shutdown();
} elseif($pid) {
    // Only the parent will know the PID. Kids aren't self-aware
    // Parent says goodbye!
    _debug("[Parent: ".getmypid()."][byebye]");
    exit(0);
}
$GLOBALS['_daemon']['role']='master';
posix_setsid(); // become session leader
chdir($GLOBALS['_daemon']['tmpDir']);
umask(0);

//  注册系统信号
_registerSignals($GLOBALS['_daemon']['role']);

$GLOBALS['_daemon']['status']='background'; //从此为后台守护进程
$GLOBALS['_daemon']['masterRun']=true;

if (!file_exists($GLOBALS['_daemon']['pidFile'])) {
    touch($GLOBALS['_daemon']['pidFile']);
}
$GLOBALS['_daemon']['pidFP']=@fopen($GLOBALS['_daemon']['pidFile'],"r+");
if (flock($GLOBALS['_daemon']['pidFP'], LOCK_EX + LOCK_NB)) {
    $GLOBALS['_daemon']['masterPid']=posix_getpid();
    fseek($GLOBALS['_daemon']['pidFP'],0);
    fputs($GLOBALS['_daemon']['pidFP'],$GLOBALS['_daemon']['masterPid']);
    ftruncate($GLOBALS['_daemon']['pidFP'],strlen($GLOBALS['_daemon']['masterPid']));
    _debug("[{$GLOBALS['OPTIONS']['title']} got lock({$GLOBALS['_daemon']['pidFile']})][pid({$GLOBALS['_daemon']['masterPid']}) saved]",_DLV_NOTICE);
} else {
    _debug("[{$GLOBALS['OPTIONS']['title']} is already running({$GLOBALS['_daemon']['pidFile']})?][quit]",_DLV_NOTICE);
    _shutdown();
}

//set title
_setProcessTitle($GLOBALS['OPTIONS']['title']);

register_shutdown_function('_onShutdown');

// Important for daemons
// See http://www.php.net/manual/en/function.pcntl-signal.php
declare(ticks = 1);

unset($moduleName);
