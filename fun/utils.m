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
        if ($GLOBALS['_enableSentinel']===true) {
            //启用了redis的哨兵机制
            foreach($GLOBALS['sentinels'] as $sentinelInfo) {
                try {
                    $sentinelConn=new Predis_Client($sentinelInfo);
                    if (!$masterInfo=$sentinelConn->sentinel('get-master-addr-by-name',$GLOBALS['sentinelMaster'])) {
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
                $GLOBALS['redisConn'] = new Predis_Client($GLOBALS['redis']);
                $GLOBALS['lockConn'] = new Predis_Client($GLOBALS['lockRedis']);
                $rt=true;
                break;
            }
        } else {
            $GLOBALS['redisConn'] = new Predis_Client($GLOBALS['redis']);
            $GLOBALS['lockConn'] = new Predis_Client($GLOBALS['lockRedis']);
            $rt=true;
        }
    } while(false);

    return $rt;
}
/* }}} */

/* {{{ _connectMysql
 */
function _connectMysql($host,$user,$pass,$db) {
    $ret = mysqli_init();
    $ret->options(MYSQLI_OPT_CONNECT_TIMEOUT, 10);
    @$ret->real_connect($host,$user,$pass,$db);
    if ($ret->connect_errno) {
        //连接失败
        return false;
    }
    return $ret;
}
/* }}} */

/* {{{ _getLock,获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
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

/* {{{ _renewLock,更新锁
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

/* {{{ _releaseLock,释放锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
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

/* {{{ _createUUID
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

/* {{{ _getFileExt
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

/* {{{ _getSubpath
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