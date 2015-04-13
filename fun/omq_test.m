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
include("fun/base.m");
include("fun/omqpoll.m");
include("fun/omq.m");
//include("fun/log.m");
include("inc/const.m");

$q=_getOmqPoller("127.0.0.1","7000");
//$q=_connectOMQ("127.0.0.1","7000");

$ts=time()-86400;
//_omqPollSet($q,"odintest","abc");
_omqPollPush($q,"dm:index:queue","campaign",'{"id":"70000067","ts":'.$ts.'}');
//$info=_omqPollPop($q,"odintest",1);
//print_r($info);
//_omqDel($q, "odintest");

