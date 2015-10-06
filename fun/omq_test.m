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

$q=_getOmqPoller("ec2-54-187-40-114.us-west-2.compute.amazonaws.com","7000");
//$q=_connectOMQ("127.0.0.1","7000");

$ts=time()-86400;
//_omqPollSet($q,"odintest","abc");
_omqPollPush($q,"dm:task:queue","nosave",'{"tag":"nosave","user":"70000021"}');
//$info=_omqPollPop($q,"odintest",1);
//print_r($info);
//_omqDel($q, "odintest");

