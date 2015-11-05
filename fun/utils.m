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

    $lockTimeout=(int)$lockTimeout>0?(int)$lockTimeout:10;  //10秒过期
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
        $lockTime=$now+$lockTimeout;
        $lockStr=$lockTime.','.$checksum;

        $tried=0;
        while($tried<$retry) {
            $tried++;
            if ($conn->setnx($lockKey,$lockStr)) {
                //获取锁
                _warn("[%s][%s][get_it!][%s][expire: %s]",__FUNCTION__,$lockKey,$lockStr,date('Y-m-d H:i:s',$lockTime));
                $rt=$checksum;
                break;
            }
            //锁存在,查看是否过期
            if ($currentLock=$conn->get($lockKey)) {
                list($currentLockTime,$currentCS)=explode(',',$currentLock);
                _warn("[%s][key: %s][currentLockTime: %s][currentCS: %s][now: %s]",__FUNCTION__,$lockKey,$currentLockTime,$currentCS,$now);
                if ($now>$currentLockTime) {
                    //过期了,抢
                    if ($lock=$conn->getset($lockKey,$lockStr)) {
                        if ($lock==$currentLock) {
                            //抢到了
                            _warn("[%s][%s][get_it!][last: %s][new: %s][expire: %s]",__FUNCTION__,$lockKey,$currentLock,$lockStr,date('Y-m-d H:i:s',$lockTime));
                            $rt=$checksum;
                            break;
                        } else {
                            //没抢到,但是覆盖了别人的锁
                        }
                    } else {
                        _error("[%s][strange_situation!!]",__FUNCTION__);
                        break;
                    }
                }
            }
            usleep(100000); //100 ms
        }
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
        $lockKey=_getSpaceName('_lock_',$ID);

        $conn->del($lockKey);
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

/* {{{ function _bcDivMod($x, $y, $base=10)
 * 大数字除法(商+余数)
 */
function _bcDivMod($x, $y, $base=10) { 
    $rt=false;
    // how many numbers to take at once? carefull not to exceed (int) 
    $take = 3;
    $mod = ''; 

    $quotient=0;
    $first=true;
    do { 
        $a = $mod.substr( $x, 0, $take ); 
        $take=strlen($x)>=$take?$take:strlen($x);
        $x = substr( $x, $take ); 
        $mod = base_convert($a,$base,10) % $y;
        $tq=base_convert((base_convert($a,$base,10)-$mod)/$y,10,$base);
        $mod=base_convert($mod,10,$base);
        if ($first) {
            $q=$tq;
            $first=false;
        } else {
            $q=sprintf("%0{$take}s",$tq);
        }
        if (!empty($quotient)) {
            $quotient.=$q;
        } else {
            $quotient=$q;
        }
        //echo "infunction: $q $quotient \n";
    } while ( strlen($x) ); 
    $rt=array(
        'mod' => base_convert($mod,$base,10),
        'quotient' => $quotient,
    );
    //echo "function result: {$mod} {$rt['mod']} {$quotient} {$rt['quotient']}\n";

    return $rt;
}

/* }}} */

/* {{{ function _shortenUUID($uuid)
 *
 */
function _shortenUUID($uuid) {
    $rt=false;
    //去掉0,1,大写O,小写l
    $alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    $shortLen = 22;

    try {
        if (empty($uuid)) {
            throw new Exception(_info("[%s][long_uuid_empty]",__FUNCTION__));
        }
        $rt="";
        $uuid=str_replace("-","",$uuid);
        $quotient=$uuid;
        while(!empty($quotient)) {
            $divmod=_bcDivMod($quotient,strlen($alphabet),16);
            $quotient=$divmod['quotient'];
            $offset=$divmod['mod'];
            $rt.=$alphabet[$offset];
        }
        $rt=str_pad($rt,$shortLen,$alphabet[0]);
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
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
    if (!empty($GLOBALS['timeZone'])) {
        $GLOBALS[$linkKey]['link']->options(MYSQLI_INIT_COMMAND, "SET SESSION time_zone = '{$GLOBALS['timeZone']}'");
    }
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
    //_notice("[%s][tag:%s][key:%s]",__FUNCTION__,$linkTag,$linkKey);
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

/* {{{ function _mysqlSafeEscapeString($linkTag, $string,$tried=0)
 * 在mysqlnd下mysqli::ping根本无效,因此这里手动重连
 */
function _mysqlSafeEscapeString($linkTag, $string,$tried=0) {
    $rt=false;

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    //_notice("[%s][tag:%s][key:%s]",__FUNCTION__,$linkTag,$linkKey);
    if ($GLOBALS[$linkKey]['link']->ping()) {  //如果php.ini设置了mysqli.reconnect = On,会尝试重连
        return $GLOBALS[$linkKey]['link']->real_escape_string($string);
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
            return _mysqlSafeEscapeString($linkTag,$string,$tried);
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
    return $GLOBALS[$linkKey]['link']->affected_rows;
}
/* }}} */

/* {{{ function _safeInsertId($linkTag)
 * 
 */
function _safeInsertId($linkTag) {

    $linkKey=_safeLinkKey($linkTag);  // adminLink,adminWLink, etc
    return $GLOBALS[$linkKey]['link']->insert_id;
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
    if ($GLOBALS[$linkKey]['transaction_in_progress']===true) {
        //已经在transaction里面了
        $GLOBALS[$linkKey]['transaction_depth']+=1;
        return true;
    }
    if ($GLOBALS[$linkKey]['link']->ping()) {  //如果php.ini设置了mysqli.reconnect = On,会尝试重连
        _info("[%s][begin]",__FUNCTION__);
        $GLOBALS[$linkKey]['transaction_in_progress']=true;
        $GLOBALS[$linkKey]['transaction_depth']=0;
        return $GLOBALS[$linkKey]['link']->autocommit(false);
    } else {
        _warn("[%s][%s][begin_transaction_failed: %s]",__FUNCTION__,$linkKey, $GLOBALS[$linkKey]['link']->error);
        if ($tried<2) {
            $tried++;
            //重连, 一次
            $host=$GLOBALS[$linkKey]['host'];
            $user=$GLOBALS[$linkKey]['user'];
            $pass=$GLOBALS[$linkKey]['pass'];
            $db=$GLOBALS[$linkKey]['db'];
            _connectSafeMysql($host,$user,$pass,$db,$linkTag);
            _warn("[%s][reconnect:%s][tried:%s][host: %s]",__FUNCTION__,$linkTag,$tried,$host);
            return _beginSafeTransaction($linkTag,$tried);
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
    if ($GLOBALS[$linkKey]['transaction_depth']>0) {
        //在transaction嵌套中
        $GLOBALS[$linkKey]['transaction_depth']-=1;
        return true;
    }
    if ($GLOBALS[$linkKey]['link']->ping()) {
        $GLOBALS[$linkKey]['transaction_in_progress']=false;
        $GLOBALS[$linkKey]['transaction_depth']=0;
        $GLOBALS[$linkKey]['link']->commit();
        return $GLOBALS[$linkKey]['link']->autocommit(true);
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
    if ($GLOBALS[$linkKey]['transaction_depth']>0) {
        //在transaction嵌套中
        $GLOBALS[$linkKey]['transaction_depth']-=1;
        return true;
    }
    if ($GLOBALS[$linkKey]['link']->ping()) {
        $GLOBALS[$linkKey]['transaction_in_progress']=false;
        $GLOBALS[$linkKey]['transaction_depth']=0;
        $GLOBALS[$linkKey]['link']->rollback();
        return $GLOBALS[$linkKey]['link']->autocommit(true);
    }

    return $rt;
}
/* }}} */

// safe lock
/* {{{ function _safeLock($ID,$lockTimeout=0)
 * 获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param int $ID, 锁ID
 * @param int $lockTimeout
 */
function _safeLock($ID,$lockTimeout=0) {
    $rt=false;

    if (empty($ID)) {
        return false;
    }
    if ($GLOBALS['_LOCK_'][$ID]['locked']===true) { //当前进程已经get到lock
        $GLOBALS['_LOCK_'][$ID]['depth']+=1;
        return true;
    }

    try {
        if (false==($lcs=_easyLock($ID,$lockTimeout))) {
            throw new Exception(_info("[%s][get_lock_failed: %s]",__FUNCTION__,$ID));
        }
        $GLOBALS['_LOCK_'][$ID]['locked']=true;
        $GLOBALS['_LOCK_'][$ID]['checksum']=$lcs;
        $GLOBALS['_LOCK_'][$ID]['ts']=time();
        $GLOBALS['_LOCK_'][$ID]['timeout']=$lockTimeout;
        $GLOBALS['_LOCK_'][$ID]['depth']=0;
        $rt=true;
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}
/* }}} */

/* {{{ function _safeRelease($ID)
 * 获取锁,这是一个用redis实现的分布式锁,保证一个id同时只有一个进程在处理
 * @param string $ID, 锁ID
 * @param bool $force,是否强制完全释放
 */
function _safeRelease($ID,$force=false) {
    $rt=false;

    if (empty($ID)) {
        return false;
    }
    if ($GLOBALS['_LOCK_'][$ID]['locked']!==true) {
        return false;
    }
    if ($GLOBALS['_LOCK_'][$ID]['depth']>0 && $force===false) { //当前进程已经get到lock
        $GLOBALS['_LOCK_'][$ID]['depth']-=1;
        return true;
    }

    try {
        $lcs=$GLOBALS['_LOCK_'][$ID]['checksum'];
        unset($GLOBALS['_LOCK_'][$ID]); //不管是否成功,$GLOBALS['_LOCK_'][$ID]都必须消失
        if (false==_easyRelease($ID,$lcs)) {
            throw new Exception(_info("[%s][get_lock_failed: %s]",__FUNCTION__,$ID));
        }
        $rt=true;
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}
/* }}} */

// temporary counter
/* {{{ function _tcAddJournal($name,$journal,$amount,$totalField="_total_")
 * 进行暂扣
 */
function _tcAddJournal($name,$journal,$amount,$totalField="_total_") {
    $rt=false;

    try {
        if (empty($name)) {
            throw new Exception(_info("[%s][name_empty]",__FUNCTION__));
        }
        if (isset($GLOBALS['RCC'])) {
            $conn=$GLOBALS['RCC'];
        } else {
            $conn=$GLOBALS['lockConn'];
        }
        if ($conn->hexists($name,$journal)) {
            //已经存在,不需要增加
            _warn("[%s][tc: %s][journal: %s][exists_and_not_need_add]",__FUNCTION__,$name,$journal);
            $rt=true;
        } else {
            //增加journal
            if (false==$conn->hset($name,$journal,$amount)) {
                throw new Exception(_info("[%s][tc: %s][journal: %s][del_failed]",__FUNCTION__,$name,$journal));
            }
            //更新总数
            if (false===$conn->hincrbyfloat($name,$totalField,$amount)) {
                throw new Exception(_info("[%s][tc: %s][journal: %s][amount: %s][upate_failed]",__FUNCTION__,$name,$journal,$mount));
            }
            $rt=true;
        }
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

/* {{{ function _tcClearJournal($name,$journal,$iAmount,$totalField)
 * 清除暂扣(实际扣除/扣除作废)
 */
function _tcClearJournal($name,$journal,$iAmount,$totalField="_total_") {
    $rt=false;

    try {
        if (empty($name)) {
            throw new Exception(_info("[%s][name_empty]",__FUNCTION__));
        }
        if (isset($GLOBALS['RCC'])) {
            $conn=$GLOBALS['RCC'];
        } else {
            $conn=$GLOBALS['lockConn'];
        }
        if ($conn->hexists($name,$journal)) {
            if (false===($amount=$conn->hget($name,$journal))) {
                throw new Exception(_info("[%s][tc: %s][journal: %s][get_failed]",__FUNCTION__,$name,$journal));
            }
            _notice("[%s][tc: %s][journal: %s][amount: %s]",__FUNCTION__,$name,$journal,$amount);
            if ($amount!=$iAmount) {
                _warn("[%s][tc: %s][journal: %s][amount: %f][input_amount: %f][diff!]",__FUNCTION__,$name,$journal,$amount,$iAmount);
            }
            //删除journal
            if (false==$conn->hdel($name,$journal)) {
                throw new Exception(_info("[%s][tc: %s][journal: %s][del_failed]",__FUNCTION__,$name,$journal));
            }
            //更新总数
            if (false===$conn->hincrbyfloat($name,$totalField,-$amount)) {
                throw new Exception(_info("[%s][tc: %s][journal: %s][amount: %s][upate_failed]",__FUNCTION__,$name,$journal,$mount));
            }
            $rt=$amount;
        } else {
            //不需要清除,返回成功
            _warn("[%s][tc: %s][journal: %s][not_exists_and_not_need_clear]",__FUNCTION__,$name,$journal);
            $rt=$iAmount;
        }
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

/* {{{ function _getInfoFromCache($cate,$key)
 * 框架内置缓存,获取
 */
function _getInfoFromCache($cate,$key=null) {
    $rt=false;

    try {
        if (empty($cate)) {
            throw new Exception(_info("[%s][cate_empty]",__FUNCTION__));
        }
        if (!empty($key)) {
            $now=time();
            if (isset($GLOBALS['_CACHE_'][$cate][$key]) && $now<=$GLOBALS['_CACHE_'][$cate][$key]['ts']) {
                $rt=$GLOBALS['_CACHE_'][$cate][$key]['info'];
            }
        } else if (isset($GLOBALS['_CACHE_'][$cate])) {    //直接返回整个cate
            $rt=$GLOBALS['_CACHE_'][$cate];
        }
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

/* {{{ function _setInfoToCache($cate,$key)
 * 框架内置缓存, 设置
 */
function _setInfoToCache($cate,$key,$info,$to=30) {
    $rt=false;

    try {
        if (empty($cate) || empty($key)) {
            throw new Exception(_info("[%s][cate_or_key_empty]",__FUNCTION__));
        }
        $to=$to<=0?30:$to;
        $exp=time()+$to; // 30秒过期
        $GLOBALS['_CACHE_'][$cate][$key]['ts']=$exp;
        $GLOBALS['_CACHE_'][$cate][$key]['info']=$info;
        $rt=true;
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

/* {{{ function _updateInfoToCache($cate,$key,$info)
 * 框架内置缓存, 设置
 */
function _updateInfoToCache($cate,$key,$info) {
    $rt=false;

    if (empty($cate) || empty($key) || empty($info)) {
        _error("[%s][cate_or_key_or_info_empty]",__FUNCTION__);
        return $rt;
    }
    if (!isset($GLOBALS['_CACHE_'][$cate][$key])) { //不需要更新
        _notice("[%s][cache_not_exists][cate: %s][$key]",__FUNCTION__,$cate,$key);
        return $rt;
    }
    try {
        $to=30;
        $exp=time()+$to; // 30秒过期
        $GLOBALS['_CACHE_'][$cate][$key]['ts']=$exp;
        foreach($info as $k=>$v) {
            $GLOBALS['_CACHE_'][$cate][$key]['info'][$k]=$v;
        }
        $rt=true;
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

/* {{{ function _flushCache($cate,$key)
 * 刷新缓存,直接删除缓存即可
 */
function _flushCache($cate,$key) {
    if (isset($GLOBALS['_CACHE_'][$cate][$key])) {
        unset($GLOBALS['_CACHE_'][$cate][$key]);
    }

    return true;
}

/* }}} */

/* {{{ function _clearCache()
 *
 */
function _clearCache() {
    unset($GLOBALS['_CACHE_']);
}

/* }}} */

/* {{{ function _spaceLock($tag,$id)
 * 支持名称空间的锁定
 */
function _spaceLock($tag,$id) {
    $rt=false;

    if (empty($tag) || empty($id)) {
        return $rt;
    }
    try {
        $lock=_getSpaceName($tag,$id);
        if (false==_safeLock($lock)) {
            throw new Exception(_info("[%s][lock_failed: %s]",__FUNCTION__,$lock));
        }
        //放到缓存
        $GLOBALS['_CACHE_']['_LOCKLIST_'][$lock]++;

        $rt=true;
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

/* {{{ function _spaceRelease()
 * 强制释放所有名称空间锁
 */
function _spaceRelease() {
    $rt=false;

    if (empty($GLOBALS['_CACHE_']['_LOCKLIST_'])) {
        return true;
    }
    try {
        foreach($GLOBALS['_CACHE_']['_LOCKLIST_'] as $lock=>$cnt) {
            _notice("[%s][lock: %s][count: %d]",__FUNCTION__,$lock,$cnt);
        }
        $rt=_safeRelease($lock,true);
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    unset($GLOBALS['_CACHE_']['_LOCKLIST_']);

    return $rt;
}

/* }}} */


