<?php
/*
  +----------------------------------------------------------------------+
  | Name:data/CDataMysql.m                                               |
  +----------------------------------------------------------------------+
  | Comment:访问mdb(HBase)的类                                           |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-04-18 23:32:30                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2013-04-16 18:35:41                                    |
  +----------------------------------------------------------------------+
*/

class CDataMysql implements IData {
    //admin server(读写分离)
    private $writeServers=array();
    private $readServers=array();
    //report(read only)
    private $reportServers=array();
    //finance(read only)
    private $financeServers=array();
    //连接变量
    private $writeHandler=null;
    private $readHandler=null;
    private $reportHandler=null;
    private $financeHandler=null;
    //连接参数
    private $rwSplitting=false; //是否读写分离
    private $timeout=2; //2s

    //mapping
    private $fieldMap=array();

    //当前连接信息
    public $connectedHost=null;
    public $connectedPort=3306;

    public $table=null;
    public $rkField='rkey'; //rowkey(pk)的字段名,可定义,默认为rk
    public $filterFields=array();   //需要过滤的字段,应该是个数组, array('field' => fileterfunction)
    public $resultFilter=null;  //结果过滤函数
    //query info
    public $query=null;
    public $code=0;
    public $rowKey=null;
    public $result=null;
    public $affected=0;
    public $rowsNum=0;

    /* {{{ 构造函数,处理初始化
     */
    public function __construct($dbConf) {
        do {
            $this->writeServers=explode(',',$dbConf['write_server']);
            if (empty($this->writeServers) || !@is_array($this->writeServers)) {
                throw new Exception("no db servers!");
                break;
            }
            if (isset($dbConf['read_server'])) {
                $this->readServers=explode(',',$dbConf['read_server']);
            }
            if (empty($this->readServers) || !@is_array($this->readServers)) {
                $this->readServers=$this->writeServers;
            } else {
                _debug("[".__METHOD__."][read/wirte split!!]",_DLV_ERROR);
                $this->rwSplitting=true;    //读写分离
            }

            $this->open();
        } while(false);
    }
    /* }}} */

    /* {{{ __destruct
     */
    public function __destruct() {
        $this->close();
    }
    /* }}} */

    /* {{{ set table
     * 指定表名称
     */
    public function setTable($table) {
        if (!empty($table)) {
            $this->table=$table;
        }
    }
    /* }}} */

    /* {{{ execute,暂时性的
     */
    public function execute($query) {
        $this->code=_ERROR_OK;
        $this->query=$query;
        _debug("[".__METHOD__."][query:{$this->query}][execute_it]",_DLV_INFO);
        try {
            //$sth=$this->writeHandler->query($query);
            //$errorInfo=$this->writeHandler->errorInfo();
            //if ($errorInfo[1]>0) {  //执行报错了
            //    $this->code=$this->getCode((int)$errorInfo[1]);
            //    $this->affected=0;
            //    _debug("[".__METHOD__."][query:{$this->query}][query_failed]",_DLV_INFO);
            //} else {
            //    $this->affected=$sth->rowCount();
            //    _debug("[".__METHOD__."][query:{$this->query}][affected:{$this->affected}]",_DLV_INFO);
            //}
            if ($sth=$this->writeHandler->query($this->query)) {
                $this->affected=$sth->rowCount();
                _debug("[".__METHOD__."][query:{$this->query}][affected:{$this->affected}]",_DLV_INFO);
            } else {
                $errorInfo=$this->writeHandler->errorInfo();
                _debug("[".__METHOD__."][query:{$this->query}][query_failed][errCode:{$errorInfo[1]}]",_DLV_INFO);
                $this->code=$this->getCode((int)$errorInfo[1]);
                $this->affected=0;
            }
        } catch (Exception $e) {
            $errorInfo=$this->writeHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }

        return $this->code;
    }
    /* }}} */

    /* {{{ query,暂时性的
     */
    public function customQuery($query) {
        $this->code=_ERROR_OK;
        $this->query=$query;
        $this->result=array();
        try {
            if ($sth=$this->readHandler->query($this->query)) {
                while($row=$sth->fetch(PDO::FETCH_ASSOC)) {
                    $this->result[]=$row;
                    $this->rowsNum++;
                }
                if ($this->rowsNum==0) {
                    $this->code=_ERROR_NOTEXISTS;
                }
            } else {
                $this->code=_ERROR_NOTEXISTS;
            }

            _debug("[".__METHOD__."][query:{$this->query}][rowsNum:{$this->rowsNum}]",_DLV_INFO);
        } catch (Exception $e) {
            $errorInfo=$this->readHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $this->code;
    }
    /* }}} */

    /* {{{ 连db server
     */
    private function open() {
        do {
            foreach ($this->writeServers as $serverInfo) {
                list($dbHost,$dbUser,$dbPass,$dbName)=explode(':',$serverInfo);
                if ($this->writeHandler = new PDO("mysql:host={$dbHost};dbname={$dbName}", $dbUser, $dbPass, array(
                    PDO::ATTR_TIMEOUT => $this->timeout,
                ))) {
                    if ($this->rwSplitting===false) {
                        _debug("[".__METHOD__."][read/write together]",_DLV_NOTICE);
                        $this->readHandler = $this->writeHandler;
                    } else {
                        _debug("[".__METHOD__."][read/write split]",_DLV_NOTICE);
                        foreach ($this->readServers as $serverInfo) {
                            list($dbHost,$dbUser,$dbPass,$dbName)=explode(':',$serverInfo);
                            if ($this->readHandler = new PDO("mysql:host={$dbHost};dbname={$dbName}", $dbUser, $dbPass, array(
                                PDO::ATTR_TIMEOUT => $this->timeout,
                            ))) {
                                break;
                            }
                        }
                    }
                    //当前连接的host
                    $this->connectedHost=$dbHost;
                    break;
                }
            }

            _debug("[".__METHOD__."][connected:{$this->connectedHost}({$this->connectedPort})]",_DLV_NOTICE);
        } while(false);
    }
    /* }}} */

    /* {{{ 关闭数据库
     */
    private function close() {
        $this->writeHandler=null;
        $this->readHandler=null;
        $this->reportHandler=null;
        $this->financeHandler=null;
    }
    /* }}} */

    /* {{{ fields=>columns
     */
    private function fields2Columns($fields) {
        foreach ($fields as $field) {
            $dbField=$field;
            $dbFields[]="`$dbField`";
            $this->fieldMap[$dbField]=$field;
        }
        return $dbFields;
    }
    /* }}} */

    /* {{{ getCode() 
     * 通过mysql错误代码获取错误代码
     */
    private function getCode($err) {
        $ret=_ERROR_DATA;
        switch ($err) {
        case 1062:
            $ret=_ERROR_CONFLICT;
            break;
        default:
            break;
        }
        return $ret;
    }
    /* }}} */

    /* {{{ get,通过rowkey获取信息,以数组返回
     * @param string $table  required
     * @param string $row    required
     * @param array  $fields required
     * @return mixed
     */
    public function iGet($table,$row,$fields) {
        $this->code=_ERROR_OK;
        try {

            if (empty($fields)) {
                $this->code=_ERROR_NOPROPERTY;
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            $this->rowKey=$row;

            $this->query="SELECT ".implode(',',$dbFields)." ".
                "FROM {$table} ".
                "WHERE `{$this->rkField}`='{$this->rowKey}' ".
                "LIMIT 1";
            if ($sth=$this->readHandler->query($this->query)) {
                if ($rows=$sth->fetch(PDO::FETCH_ASSOC)) {
                    $this->rowsNum=1;
                    $this->result['rowKey']=$this->rowKey;
                    foreach ($rows as $column=>$value) {
                        if ($column!=$this->rkField) {
                            if (isset($this->filterFields[$this->fieldMap[$column]]) && function_exists($this->filterFields[$this->fieldMap[$column]])) {
                                $this->result['item'][$this->fieldMap[$column]]=call_user_func($this->filterFields[$this->fieldMap[$column]],$value);
                            } else {
                                $this->result['item'][$this->fieldMap[$column]]=$value;
                            }
                        }
                    }
                    if (!empty($this->resultFilter) && function_exists($this->resultFilter)) {
                        _debug("[".__METHOD__."][resultFilter:{$this->resultFilter}]",_DLV_NOTICE);
                        $this->result=call_user_func($this->resultFilter,$this->result);
                    }
                }
                if ($this->rowsNum==0) {
                    $this->code=_ERROR_NOTEXISTS;
                }
            } else {
                $this->code=_ERROR_NOTEXISTS;
            }
            _debug("[".__METHOD__."][query:{$this->query}][row_num:{$this->rowsNum}]",_DLV_NOTICE);
        } catch (Exception $e) {
            $errorInfo=$this->readHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $this->code;
    }
    /* }}} */

    /* {{{ BatchGet, 可同时获取多个rowkey信息
     * @param string $table  required
     * @param array  $rows   required
     * @param array  $fields required
     * @return mixed
     */
    public function iBatchGet($table,$rows,$fields) {
        $this->code=_ERROR_OK;
        try {
            if (empty($rows)) {
                $this->code=_ERROR_NOKEY;
                throw new Exception("no rows!");
            } elseif (empty($fields)) {
                $this->code=_ERROR_NOPROPERTY;
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            $this->query="SELECT ".implode(',',$dbFields)." FROM {$table} WHERE `{$this->rkField}` IN (".implode(',',$rows).")";
            if ($sth=$this->readHandler->query($this->query)) {
                while($row=$sth->fetch(PDO::FETCH_ASSOC)) {
                    $this->result[$this->rowsNum]['rowKey']=$row[$this->rkField];
                    foreach ($row as $column=>$value) {
                        if ($column!=$this->rkField) {
                            if (isset($this->filterFields[$this->fieldMap[$column]]) && function_exists($this->filterFields[$this->fieldMap[$column]])) {
                                $this->result[$this->rowsNum]['item'][$this->fieldMap[$column]]=call_user_func($this->filterFields[$this->fieldMap[$column]],$value);
                            } else {
                                $this->result[$this->rowsNum]['item'][$this->fieldMap[$column]]=$value;
                            }
                        }
                    }
                    $this->rowsNum++;
                }
                if ($this->rowsNum==0) {
                    $this->code=_ERROR_NOTEXISTS;
                }
            } else {
                $this->code=_ERROR_NOTEXISTS;
            }

            _debug("[".__METHOD__."][query:{$this->query}][rowsNum:{$this->rowsNum}]",_DLV_INFO);
        } catch (Exception $e) {
            $errorInfo=$this->readHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $this->code;
    }
    /* }}} */

    /* {{{ Put, 写入rowkey(rowkey为空则insert(并产生一个rowkey返回),存在则更新)
     * @param string $table  required
     * @param string $row    required
     * @param array  $data   required   一个多维数组, array('col'=>array('value'=>{value}, 'index'=>{qualifier}))
     * @return mixed
     */
    public function iPut($table,$row,$data) {
        $this->code=_ERROR_OK;
        try {

            if (empty($data)) {
                $this->code=_ERROR_NOPROPERTY;
                throw new Exception("no data!");
            }

            if (!empty($row)) { //update
                $this->rowKey=$row;
                foreach ($data as $col=>$info) {
                    if (!isset($info['type']) || $info['type']=='S') {  // 空或者S都代表字符串,加单引号
                        $arrUp[]="`{$col}`='{$info['value']}'";
                    } else {
                        $arrUp[]="`{$col}`={$info['value']}";
                    }
                }
                $strUpdate=implode(',',$arrUp);
                $this->query="UPDATE `{$table}`".
                    "SET {$strUpdate} ".
                    "WHERE `{$this->rkField}`='{$this->rowKey}'";
            } else {//insert
                //$this->rowKey=_createGuid($GLOBALS['serviceName']);   //生成一个独立id
                //$arrCols[]='`rkey`';
                //$arrVals[]="'{$this->rowKey}'";
                foreach ($data as $col=>$info) {
                    $arrCols[]="`{$col}`";
                    if (!isset($info['type']) || $info['type']=='S') {  // 空或者S都代表字符串,加单引号
                        $arrVals[]="'{$info['value']}'";
                    } else {
                        $arrVals[]="{$info['value']}";
                    }
                }
                $this->query="INSERT INTO `{$table}`".
                    "(".implode(',',$arrCols).") ".
                    "VALUES(".implode(',',$arrVals).")";
            }

            //insert 
            if ($sth=$this->writeHandler->query($this->query)) {
                $this->affected=$sth->rowCount();
            }

            _debug("[".__METHOD__."][query:{$this->query}][affected:{$this->affected}]",_DLV_INFO);
        } catch (Exception $e) {
            $errorInfo=$this->writeHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $this->code;
    }
    /* }}} */

    /* {{{ Delete, 删除rowkey
     * @param string $table  required
     * @param array  $row    required
     * @param array  $fields required  需要删除的字段信息,如果这个参数为null,则删除整个row!
     * @return mixed
     */
    public function iDelete($table,$row,$fields=null) {
        $this->code=_ERROR_OK;
        try {
            $this->query="DELETE FROM `{$table}` ".
                "WHERE `{$this->rkField}`='$row'";

            //delete
            if ($sth=$this->writeHandler->query($this->query)) {
                $this->affected=$sth->rowCount();
            }
            _debug("[".__METHOD__."][query:{$this->query}][affected:{$this->affected}]",_DLV_INFO);
        } catch (Exception $e) {
            $errorInfo=$this->writeHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $this->code;
    }
    /* }}} */
    
    /* {{{ BatchWrite, 可同时写入多个rowkey(字段的更新删除均可,但不可删除整个row)
     * @param string $table       required
     * @param array  $batchRows   required   一个多维数组, array({row} => array('col'=>array('value'=>{value}, 'index'=>{qualifier},'delete'=>{1/0})))
     * @return mixed
     */
    public function iBatchWrite($table,$batchRows) {
        $ret=false;
        return $ret;
    }
    /* }}} */

    /* {{{ scan,用来扫描表,也可以传入查询条件(前提是存为index类型的column)
     * @param string $table  required
     * @param array  $fields required
     * @param string $startRow not required
     * @param array  $conds  not required 查询条件  array({qualifier}=>{value})     如果要查询字段是property:status,则qualifier为status
     * @param int    $count  default    最大500
     * @return mixed
     */
    public function iScan($table,$fields,$conds=null,$startRow=0,$count=1) {
        $this->code=_ERROR_OK;

        try {
            if (empty($fields)) {
                $this->code=_ERROR_NOPROPERTY;
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            //确定最大返回条目
            if ($count>$GLOBALS['maxLimit']) {
                $count=$GLOBALS['maxLimit'];
            }

            if (!empty($conds)) {   //传入了查询条件
                $strCond=implode(' AND ',$conds);
            } else {
                $strCond='1=1';
            }

            //limit str
            if ($count>0) {
                $limitStr=" LIMIT {$startRow},{$count}";
            } else {
                $limitStr='';
            }

            $this->query="SELECT ".implode(',',$dbFields)." ".
                "FROM `{$table}` ".
                "WHERE {$strCond} ".
                "ORDER BY `created` DESC".
                "{$limitStr}";
            if ($sth=$this->readHandler->query($this->query)) {
                $this->rowsNum=0;
                while($rows=$sth->fetch(PDO::FETCH_ASSOC)) {
                    $this->result[$this->rowsNum]['rowKey']=$rows[$this->rkField];
                    foreach ($rows as $column=>$value) {
                        if ($column!=$this->rkField) {
                            if (isset($this->filterFields[$this->fieldMap[$column]]) && function_exists($this->filterFields[$this->fieldMap[$column]])) {
                                $this->result[$this->rowsNum]['item'][$this->fieldMap[$column]]=call_user_func($this->filterFields[$this->fieldMap[$column]],$value);
                            } else {
                                $this->result[$this->rowsNum]['item'][$this->fieldMap[$column]]=$value;
                            }
                        }
                    }
                    if (!empty($this->resultFilter) && function_exists($this->resultFilter)) {
                        _debug("[".__METHOD__."][resultFilter:{$this->resultFilter}]",_DLV_NOTICE);
                        $this->result[$this->rowsNum]=call_user_func($this->resultFilter,$this->result[$this->rowsNum]);
                    }
                    $this->rowsNum++;
                }
                if ($this->rowsNum==0) {
                    $this->code=_ERROR_NOTEXISTS;
                }
            } else {
                $this->code=_ERROR_NOTEXISTS;
            }
            _debug("[".__METHOD__."][query:{$this->query}][rows_num:{$this->rowsNum}]",_DLV_INFO);
        } catch (Exception $e) {
            $errorInfo=$this->readHandler->errorInfo();
            $this->code=$this->getCode((int)$errorInfo[1]);
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }

        return $this->code;
    }
    /* }}} */

    /* {{{ query, 这个应该可以进行范围请求
     */
    public function iQuery() {
        return null;
    }
    /* }}} */
}
