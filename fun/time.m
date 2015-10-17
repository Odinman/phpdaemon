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

/* {{{ function _getTS($tsStr,$format)
 * 从字符串获取时间戳
 */
function _getTS($tsStr,$format='RFC3339NANO') {
    $rt=false;

    try {
        if (empty($tsStr)) {
            throw new Exception(_info("[%s][time_string_empty]",__FUNCTION__));
        }
        switch(strtoupper($format)) {
        case 'RFC3339NANO': //3339到纳秒(php最多处理到微秒)  "2006-01-02T15:04:05.999999999-07:00"
            $tsStr=preg_replace('/\.\d{0,}([Z+-])/',"$1",$tsStr);
            $d=new DateTime($tsStr);
            $rt=$d->getTimestamp();
            break;
        case 'RFC3339MICRO': // "2006-01-02T15:04:05.999999-07:00"  ,到微秒
        case 'RFC3339': // "2006-01-02T15:04:05Z07:00"
        default:
            $d=new DateTime($tsStr);
            $rt=$d->getTimestamp();
            break;
        }
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */

