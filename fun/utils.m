<?php
/*
  +----------------------------------------------------------------------+
  | Name:                                                                |
  +----------------------------------------------------------------------+
  | Comment:                                                             |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:TIMESTAMP                              |
  +----------------------------------------------------------------------+
  | Last-Modified:TIMESTAMP                        |
  +----------------------------------------------------------------------+
*/

/* {{{ function _getRedisConnections()
 */
function _getRedisConnections() {
    $rt=false;

    do {
        $GLOBALS['ciRedisConn'] = new Predis\Client($GLOBALS['ciRedis']);
        if ($GLOBALS['_enableSentinel']===true) {
            //启用了redis的哨兵机制
            foreach($GLOBALS['sentinels'] as $sentinelInfo) {
                try {
                    $sentinelConn=new Predis\Client($sentinelInfo);
                    if (!$masterInfo=$sentinelConn->executeRaw('SENTINEL','get-master-addr-by-name',$GLOBALS['sentinelMaster'])) {
                        throw new Exception('Find Master Failed!');
                    }
                    _notice("[%s][master:%s][port:%s]",__FUNCTION__,$masterInfo[0], $masterInfo[1]);
                    //出价以及锁的redis一致
                    $GLOBALS['redis']['host']=$masterInfo[0];
                    $GLOBALS['redis']['port']=$masterInfo[1];
                    $GLOBALS['lockRedis']['host']=$masterInfo[0];
                    $GLOBALS['lockRedis']['port']=$masterInfo[1];
                } catch (Exception $e) {
                    _warn("[%s][Exception: %s]",__FUNCTION__,$e->getMessage());
                }
                $GLOBALS['redisConn'] = new Predis\Client($GLOBALS['redis']);
                $GLOBALS['lockConn'] = new Predis\Client($GLOBALS['lockRedis']);
                $rt=true;
                break;
            }
        } else {
            $GLOBALS['redisConn'] = new Predis\Client($GLOBALS['redis']);
            $GLOBALS['lockConn'] = new Predis\Client($GLOBALS['lockRedis']);
            $rt=true;
        }
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _getRedisConn($server_info)
 */
function _getRedisConn($server_info) {
    $rt=false;

    do {
        $rt=new Predis\Client($server_info);
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _getRedisCluster($servers)
 */
function _getRedisCluster($servers) {
    $rt=false;

    do {
        if (empty($servers)) {
            _warn("[%s][not_found_any_server]",__FUNCTION__);
            break;
        }
        $rt=new Predis\Client($servers,['cluster' => 'redis']);
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _getLock($conn,$ID,$checksum, $lockPrefix=null,$lockTimeout=0)
 * 获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param resource $conn, redis连接
 * @param int $ID, 锁ID
 * @param string $checksum
 */
function _getLock($conn,$ID,$checksum, $lockPrefix=null,$lockTimeout=0) {
    $rt=false;

    $lockPrefix=$lockPrefix===null?"_lock_":$lockPrefix;
    $lockTimeout=(int)$lockTimeout>0?(int)$lockTimeout:30;

    do {
        if (!$conn || empty($ID)) {
            _warn("[%s][id: %s][no_conn]",__FUNCTION__,$ID);
            break;
        }
        $now=time();
        $lockKey=$lockPrefix.':'.$ID;

        $conn->watch($lockKey);
        if ($currentLock=$conn->get($lockKey)) {    //存在锁
            list($currentLockTime,$currentCS)=explode(',',$currentLock);
            if ($currentLockTime>$now) {    //当前有锁且没有过期,失败
                $conn->unwatch();
                break;
            } 
        }

        //key不存在,或者已经过期
        $lockTime=$now+$lockTimeout;
        $lockStr=$lockTime.','.$checksum;
        $conn->multi();
        $conn->set($lockKey,$lockStr);
        if (!$conn->exec()) {    //很不幸,被抢了
            _warn("[%s][%s][get_failed]",__FUNCTION__,$lockKey);
            break;
        }
        _warn("[%s][%s][get_it!][checksum: %s][expire: %s]",__FUNCTION__,$lockKey,$checksum,date('Y-m-d H:i:s',$lockTime));
        $rt=true;
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _easyLock($ID,$lockTimeout=0)
 * 获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param int $ID, 锁ID
 * @param int $lockTimeout
 */
function _easyLock($ID,$lockTimeout=0) {
    $rt=false;

    $lockTimeout=(int)$lockTimeout>0?(int)$lockTimeout:30;
    $retry=$GLOBALS['_tryLock']>0?$GLOBALS['_tryLock']:5;

    do {
        if (empty($ID)) {
            _warn("[%s][no_id]",__FUNCTION__);
            break;
        }
        if (isset($GLOBALS['RCC'])) {
            $conn=$GLOBALS['RCC'];
        } else {
            $conn=$GLOBALS['lockConn'];
        }
        $checksum=_createUUID();
        $now=time();
        $lockKey=_getSpaceName('_lock_',$ID);

        $tried=0;
        while($tried<$retry) {
            $tried++;
            $conn->watch($lockKey);
            if ($currentLock=$conn->get($lockKey)) {    //存在锁
                list($currentLockTime,$currentCS)=explode(',',$currentLock);
                _warn("[%s][key: %s][currentLockTime: %s][currentCS: %s][now: %s]",__FUNCTION__,$lockKey,$currentLockTime,$currentCS,$now);
                if ($currentLockTime>$now) {    //当前有锁且没有过期,失败
                    $conn->unwatch();
                    usleep(500000); //500 ms
                    continue;
                }
            }
            //key不存在,或者已经过期
            $lockTime=$now+$lockTimeout;
            $lockStr=$lockTime.','.$checksum;
            $conn->multi();
            $conn->set($lockKey,$lockStr);
            $conn->expire($lockKey,600);
            if (!$conn->exec()) {    //很不幸,被抢了
                usleep(500000); //500 ms
                _warn("[%s][%s][get_failed]",__FUNCTION__,$lockKey);
            } else {
                _warn("[%s][%s][get_it!][checksum: %s][expire: %s]",__FUNCTION__,$lockKey,$checksum,date('Y-m-d H:i:s',$lockTime));
                $rt=$checksum;
                break;
            }
        }
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _easyRenew($ID,$checksum,$lockTimeout=0)
 * 获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param int $ID, 锁ID
 * @param string $checksum
 * @param int $lockTImeout
 */
function _easyRenew($ID,$checksum,$lockTimeout=0) {
    $rt=false;

    $lockTimeout=(int)$lockTimeout>0?(int)$lockTimeout:300;

    do {
        if (empty($ID)) {
            break;
        }
        if (isset($GLOBALS['RCC'])) {
            $conn=$GLOBALS['RCC'];
        } else {
            $conn=$GLOBALS['lockConn'];
        }
        $now=time();
        $lockKey=_getSpaceName('_lock_',$ID);

        $conn->watch($lockKey);
        if (!$currentLock=$conn->get($lockKey)) {    //锁没了
            $conn->unwatch();
            break;
        }
        list($currentLockTime,$currentCS)=explode(',',$currentLock);
        if ($currentLockTime<$now) {    //过期
            $conn->unwatch();
            break;
        } elseif ($currentCS!=$checksum) {    //owner不是自己
            $conn->unwatch();
            break;
        } 

        //key存在,并且没有过期,更新之
        $lockTime=$now+$lockTimeout;
        $lockStr=$lockTime.','.$checksum;
        $conn->multi();
        $conn->set($lockKey,$lockStr);
        if (!$conn->exec()) {    //很不幸,被抢了
            _warn("[%s][%s][get_failed]",__FUNCTION__,$lockKey);
            break;
        }
        _warn("[%s][%s][renew_it!][checksum: %s][expire: %s]",__FUNCTION__,$lockKey,$checksum,date('Y-m-d H:i:s',$lockTime));
        $rt=true;
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _easyRelease($ID,$checksum)
 * 获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param int $ID, 锁ID
 * @param string $checksum
 */
function _easyRelease($ID,$checksum) {
    $rt=false;

    do {
        if (empty($ID)) {
            break;
        }
        if (isset($GLOBALS['RCC'])) {
            $conn=$GLOBALS['RCC'];
        } else {
            $conn=$GLOBALS['lockConn'];
        }
        $now=time();
        $lockKey=_getSpaceName('_lock_',$ID);

        $conn->watch($lockKey);
        if (!$currentLock=$conn->get($lockKey)) {    //锁没了
            $conn->unwatch();
            break;
        }
        list($currentLockTime,$currentCS)=explode(',',$currentLock);
        if ($currentLockTime<$now) {    //过期
            $conn->unwatch();
            break;
        } elseif ($currentCS!=$checksum) {    //owner不是自己
            $conn->unwatch();
            break;
        } 
        //锁没有过期并且owner是自己
        $conn->multi();
        $conn->del($lockKey);
        if (!$conn->exec()) {    // 删除成功
            _warn("[%s][%s][get_failed]",__FUNCTION__,$lockKey);
            break;
        }
        $rt=true;
        _warn("[%s][%s][release_it!][checksum: %s]",__FUNCTION__,$lockKey,$checksum);
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _renewLock($conn,$ID,$checksum,$lockPrefix=null,$lockTimeout=0)
 * 更新锁
 * @param resource $conn, redis连接
 * @param int $ID, id
 */
function _renewLock($conn,$ID,$checksum,$lockPrefix=null,$lockTimeout=0) {
    $rt=false;

    $lockPrefix=$lockPrefix===null?"_lock_":$lockPrefix;
    $lockTimeout=(int)$lockTimeout>0?(int)$lockTimeout:300;

    do {
        if (!$conn || empty($ID)) {
            break;
        }
        $now=time();
        $lockKey=$lockPrefix.':'.$ID;

        $conn->watch($lockKey);
        if (!$currentLock=$conn->get($lockKey)) {    //锁没了
            $conn->unwatch();
            break;
        }
        list($currentLockTime,$currentCS)=explode(',',$currentLock);
        if ($currentLockTime<$now) {    //过期
            $conn->unwatch();
            break;
        } elseif ($currentCS!=$checksum) {    //owner不是自己
            $conn->unwatch();
            break;
        } 

        //key存在,并且没有过期,更新之
        $lockTime=$now+$lockTimeout;
        $lockStr=$lockTime.','.$checksum;
        $conn->multi();
        $conn->set($lockKey,$lockStr);
        if (!$conn->exec()) {    //很不幸,被抢了
            _warn("[%s][%s][get_failed]",__FUNCTION__,$lockKey);
            break;
        }
        _warn("[%s][%s][renew_it!][checksum: %s][expire: %s]",__FUNCTION__,$lockKey,$checksum,date('Y-m-d H:i:s',$lockTime));
        $rt=true;
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _releaseLock($conn,$ID,$checksum,$lockPrefix=null)
 * 释放锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param resource $conn, redis连接
 * @param int $ID, id
 */
function _releaseLock($conn,$ID,$checksum,$lockPrefix=null) {
    $rt=false;

    $lockPrefix=$lockPrefix===null?"_lock_":$lockPrefix;

    do {
        if (!$conn || empty($ID)) {
            break;
        }
        $now=time();
        $lockKey=$lockPrefix.':'.$ID;

        $conn->watch($lockKey);
        if (!$currentLock=$conn->get($lockKey)) {    //锁没了
            $conn->unwatch();
            break;
        }
        list($currentLockTime,$currentCS)=explode(',',$currentLock);
        if ($currentLockTime<$now) {    //过期
            $conn->unwatch();
            break;
        } elseif ($currentCS!=$checksum) {    //owner不是自己
            $conn->unwatch();
            break;
        } 
        //锁没有过期并且owner是自己
        $conn->multi();
        $conn->del($lockKey);
        if (!$conn->exec()) {    // 删除成功
            _warn("[%s][%s][get_failed]",__FUNCTION__,$lockKey);
            break;
        }
        $rt=true;
        _warn("[%s][%s][release_it!][checksum: %s]",__FUNCTION__,$lockKey,$checksum);
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ function _createUUID($namespace = '')
 */
function _createUUID($namespace = '') {
    static $uuid = '';
    $uid = uniqid("", true);
    $data = $namespace;
    $data .= _microtimeFloat();
    $data .= $_SERVER['HOSTNAME'];
    $hash = strtolower(hash('ripemd128', $uid . $uuid . md5($data)));
    $uuid = substr($hash,  0,  8) .
        '-' .
        substr($hash,  8,  4) .
        '-' .
        substr($hash, 12,  4) .
        '-' .
        substr($hash, 16,  4) .
        '-' .
        substr($hash, 20, 12);
    return $uuid;
}
/* }}} */

/* {{{ function _getFileExt($mimetype)
 */
function _getFileExt($mimetype) {
    $ret=false;
    $arrayMimeType=array(
        'image/png' => 'png',
        'image/jpeg' => 'jpg',
        'image/gif' => 'gif',
        'application/x-javascript' => 'js',
        'application/x-shockwave-flash' => 'swf',
        'text/html' => 'html',
        //'text/plain' => 'html',
        'video/mp4' => 'mp4',
        'audio/x-wav' => 'wav',
        'audio/mpeg' => 'mp3',
        'video/mpeg' => 'mpg',
        'video/x-ms-wmv' => 'wmv',
        'video/x-pn-realvideo' => 'rmvb',
        'application/zip' => 'zip',
        'application/x-rar-compressed' => 'rar',
        'application/vnd.android.packagearchive' => 'apk',
        'video/3gpp' => '3gp',
        'video/3gpp' => '3gpp',
        'video/x-flv' => 'flv',
    );
    if (isset($arrayMimeType[$mimetype])) {
        $ret=$arrayMimeType[$mimetype];
    }
    return $ret;
}
/* }}} */

/* {{{ function _getSubpath($rowKey)
 */
function _getSubpath($rowKey) {
    $rt='00/00';

    do {
        if (empty($rowKey)) {
            break;
        }
        $cs=md5($rowKey);
        //$cs=$rowKey;
        $rt=substr($cs,9,2).'/'.substr($cs,14,2);
    } while(false);
    return $rt;
}
/* }}} */

/* {{{  function _getRemoteContent($url)
 *
 */
function _getRemoteContent($url) {
    $rt = false;

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'GET');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    //curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    //curl_setopt($ch, CURLOPT_HEADER, 1);
    $output = curl_exec($ch);
    $info = curl_getinfo($ch);

    if ($info['http_code']==200) {
        _notice("[%s][get: %s]", __FUNCTION__,$url);
        $rt=$output;
    } else {
        _notice("[%s][failed: %s]", __FUNCTION__,$url);
    }

    curl_close($ch);
    return $rt;
}

/* }}} */

/* {{{ function _getSpaceName($prefix,$tag=null) {
 * 获取缓存key,这里支持name space
 */
function _getSpaceName($prefix,$tag=null) {
    $rt=false;

    do {
        if (empty($prefix)) {
            break;
        }
        $rt=$prefix.$GLOBALS['NS_SUFFIX'];  // 如果存在namespace
        if (!empty($tag)) {
            $rt.=":{$tag}";
        }
    } while(false);

    return $rt;
}
/* }}} */

// mysql
/* {{{ function _connectMysql($host,$user,$pass,$db)
 */
function _connectMysql($host,$user,$pass,$db) {
    $rt = mysqli_init();
    $rt->options(MYSQLI_OPT_CONNECT_TIMEOUT, 10);
    $rt->options(MYSQLI_INIT_COMMAND, "SET NAMES utf8");
    @$rt->real_connect($host,$user,$pass,$db);
    if ($rt->connect_errno) {
        //连接失败
        return false;
    }
    return $rt;
}
/* }}} */

/* {{{ function _safeKey($tag)
 *
 */
function _safeLinkKey($tag) {
    return "{$tag}SafeLink";
}
/* }}} */

/* {{{ function _connectSafeMysql($host,$user,$pass,$db)
 */
function _connectSafeMysql($host,$user,$pass,$db,$linkTag) {
    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    $GLOBALS[$linkKey]=array(
        'host' => $host,
        'user' => $user,
        'pass' => $pass,
        'db' => $db,
    );
    $GLOBALS[$linkKey]['link'] = mysqli_init();
    $GLOBALS[$linkKey]['link']->options(MYSQLI_OPT_CONNECT_TIMEOUT, 10);
    $GLOBALS[$linkKey]['link']->options(MYSQLI_INIT_COMMAND, "SET NAMES utf8");
    @$GLOBALS[$linkKey]['link']->real_connect($host,$user,$pass,$db);
    if ($GLOBALS[$linkKey]['link']->connect_errno) {
        //连接失败
        _error("[%s]connect %s error: %s",__FUNCTION__,$linkTag,$GLOBALS[$linkKey]['link']->error);
        return false;
    }
    return true;
}
/* }}} */

/* {{{ function _mysqlExecute($mysqli, $sql)
 *
 */
function _mysqlExecute($mysqli, $sql) {
    $rt=false;

    if ($mysqli->ping()) {  //如果php.ini设置了mysqli.reconnect = On,会尝试重连
        return $mysqli->query($sql);
    }

    _warn("[%s][%s][query_failed: %s]",__FUNCTION__,$sql, $mysqli->error);

    return $rt;
}
/* }}} */

/* {{{ function _mysqlSafeExecute($linkTag, $sql)
 * 在mysqlnd下mysqli::ping根本无效,因此这里手动重连
 */
function _mysqlSafeExecute($linkTag, $sql,$tried=0) {
    $rt=false;

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    if ($GLOBALS[$linkKey]['link']->ping()) {  //如果php.ini设置了mysqli.reconnect = On,会尝试重连
        return $GLOBALS[$linkKey]['link']->query($sql);
    } else {

        _warn("[%s][%s][query_failed: %s]",__FUNCTION__,$sql, $GLOBALS[$linkKey]['link']->error);
        if ($GLOBALS[$linkKey]['transaction_in_progress']!==true && $tried<2) { // trasaction要求不能断线
            $tried++;
            //重连, 一次
            $host=$GLOBALS[$linkKey]['host'];
            $user=$GLOBALS[$linkKey]['user'];
            $pass=$GLOBALS[$linkKey]['pass'];
            $db=$GLOBALS[$linkKey]['db'];
            _connectSafeMysql($host,$user,$pass,$db,$linkTag);
            _warn("[%s][reconnect:%s][tried:%s]",__FUNCTION__,$linkTag,$tried);
            return _mysqlSafeExecute($linkTag,$sql,$tried);
        }

    }

    return $rt;
}
/* }}} */

/* {{{ function _safeAffectedRows($linkTag)
 * 
 */
function _safeAffectedRows($linkTag) {

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    return $GLOBALS[$linkKey]['link']->affectd_rows;
}
/* }}} */

/* {{{ function _safeError($linkTag)
 * 
 */
function _safeError($linkTag) {

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    return $GLOBALS[$linkKey]['link']->error;
}
/* }}} */

/* {{{ function _beginSafeTransaction($linkTag,$tried=0) 
 *
 */
function _beginSafeTransaction($linkTag,$tried=0) {
    $rt=false;

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    if ($GLOBALS[$linkKey]['link']->ping()) {  //如果php.ini设置了mysqli.reconnect = On,会尝试重连
        $GLOBALS[$linkKey]['transaction_in_progress']=true;
        return $GLOBALS[$linkKey]['link']->autocommit(false);
    } else {
        _warn("[%s][%s][query_failed: %s]",__FUNCTION__,$sql, $GLOBALS[$linkKey]['link']->error);
        if ($tried<2) {
            $tried++;
            //重连, 一次
            $host=$GLOBALS[$linkKey]['host'];
            $user=$GLOBALS[$linkKey]['user'];
            $pass=$GLOBALS[$linkKey]['pass'];
            $db=$GLOBALS[$linkKey]['db'];
            _connectSafeMysql($host,$user,$pass,$db,$linkTag);
            _warn("[%s][reconnect:%s][tried:%s]",__FUNCTION__,$linkTag,$tried);
            return _beginTransaction($linkTag,$tried);
        }

    }

    return $rt;
}
/* }}} */

/* {{{ function _safeCommit($linkTag) 
 *
 */
function _safeCommit($linkTag) {
    $rt=false;

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    if ($GLOBALS[$linkKey]['link']->ping()) {
        $GLOBALS[$linkKey]['transaction_in_progress']=false;
        return $GLOBALS[$linkKey]['link']->commit();
    }

    return $rt;
}
/* }}} */

/* {{{ function _safeRollback($linkTag) 
 *
 */
function _safeRollback($linkTag) {
    $rt=false;

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    if ($GLOBALS[$linkKey]['link']->ping()) {
        $GLOBALS[$linkKey]['transaction_in_progress']=false;
        return $GLOBALS[$linkKey]['link']->rollback();
    }

    return $rt;
}
/* }}} */
