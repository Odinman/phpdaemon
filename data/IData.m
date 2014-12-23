<?php
/*
  +----------------------------------------------------------------------+
  | Name:dataIf.m                                                        |
  +----------------------------------------------------------------------+
  | Comment:数据接口                                                     |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-04-08 23:43:19                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2012-06-23 15:38:13                                    |
  +----------------------------------------------------------------------+
*/

interface IData {
    public function iGet($table,$row,$fields);

    public function iBatchGet($table,$rows,$fields);

    public function iPut($table,$row,$data);

    public function iDelete($table,$row,$fields=null);

    public function iBatchWrite($table,$batchRows);

    public function iScan($table,$fields,$conds=null,$startRow='',$count=50);

    public function iQuery();
}
