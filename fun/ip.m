<?php
/*
  +----------------------------------------------------------------------+
  | Name:fun/ip.m                                                        |
  +----------------------------------------------------------------------+
  | Comment:IP函数                                                       |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2010-10-26 11:24:28                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2012-08-28 21:25:55                                    |
  +----------------------------------------------------------------------+
*/

/** usertype **/
define('_USERTYPE_UNKNOWN','00');
define('_USERTYPE_CMWAP',  '01');
define('_USERTYPE_CMNET',  '02');
define('_USERTYPE_CTWAP',  '03');
define('_USERTYPE_CTNET',  '04');
define('_USERTYPE_UNIWAP', '05');
define('_USERTYPE_UNINET', '06');
define('_USERTYPE_WIFI',   '07');
define('_USERTYPE_TRUST',  '97');  //信任的IP
define('_USERTYPE_BLACK',  '99');  //黑名单
//以上是能从网关直接判断的用户类型',以下需要其他信息
define('_USERTYPE_MISC',   '98');  //MISC服务器IP或者白名单
define('_USERTYPE_COOKIE', '101');
define('_USERTYPE_MCMWAP', '102');
define('_USERTYPE_TEST',   '103');

/* {{{ madhouse打包函数,注意取值范围
 */
function madPack($arrPack) {
    $ret='';
    if (!empty($arrPack)) {
        foreach ($arrPack as $value) {
            $ret.=chr((int)$value);
        }
    }
    return $ret;
}
function madUnPack($packStr) {
    $ret=false;
    if (!empty($packStr)) {
        for ($i=0;$i<strlen($packStr);$i++) {
            $ret[]=ord($packStr[$i]);
        }
    }
    return $ret;
}
/* }}} */
/* {{{ 获取某个ipv4的ip的classB(前16位)的偏移量
 */
function getClassBOffset($ip) {
    $ipLong=ip2long($ip)>>16;
    return $ipLong<0?$ipLong&65535:$ipLong;
}
/* }}} */

/* {{{ 获取某个ipv4的ip(17到25位)的偏移量
 */
function get17To25Offset($ip) {
    $ipLong=ip2long($ip);
    return ($ipLong&65408)>>7;    //65408:00000000.00000000.11111111.10000000
}
/* }}} */

function gatewayInfo($gateway,$ipIdxFile='/services/accounting/conf/IPZHCN.idx') {
    $ipInfo=false;
    /*{{{  先判断国内
     */
    $province='0000';
    $carrier='00';
    if (file_exists($ipIdxFile) && $idxFp=@fopen($ipIdxFile,"rb")) {
        $indexOffset=getClassBOffset($gateway);
        fseek($idxFp,$indexOffset*4);
        $offsetInfo=fread($idxFp,4);
        $arrOff=unpack('N*',$offsetInfo);
        $infoStartOffset=$arrOff[1];
        if ($infoStartOffset>0) {
            $offset_1725=get17To25Offset($gateway);
            $infoOffset=$infoStartOffset+$offset_1725*2;
            fseek($idxFp,$infoOffset);
            $ipInfoStr=fread($idxFp,2);
            $ipDetail=madUnPack($ipInfoStr);
            $province=sprintf('%04s',$ipDetail[0]);
            $carrier=sprintf('%02s',$ipDetail[1]);
        }
        fclose($idxFp);
    }
    $ipInfo['province']=$province;
    /*}}}*/
    $ipInfo['userType']=$carrier;
    return $ipInfo;
}
?>
