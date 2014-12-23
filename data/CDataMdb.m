<?php
/*
  +----------------------------------------------------------------------+
  | Name:data/CDataMdb.m                                                 |
  +----------------------------------------------------------------------+
  | Comment:访问mdb(HBase)的类                                           |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-04-18 23:32:30                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2012-09-15 15:11:06                                    |
  +----------------------------------------------------------------------+
*/

class CDataMdb implements IData {
    //
    private $dbServers=array();
    private $dbHosts=array();
    private $dbPorts=array();
    //连接变量
    private $protocol=null;
    private $transport=null;
    private $client=null;
    private $socket=null;
    //连接参数
    private $sendTimeout=20000; //20s
    private $recvTimeout=60000;

    //字段family
    private $singleFamily='property';
    //mapping
    private $fieldMap=array();

    //当前连接信息
    public $connectedHost=null;
    public $connectedPort=null;

    /* {{{ 构造函数,处理初始化
     */
    public function __construct($dbConf) {
        $this->dbServers=explode(',',$dbConf['server']);

        include_once(_DAEMON_ROOT.'lib/thrift/Thrift.php');
        include_once(_DAEMON_ROOT.'lib/thrift/protocol/TBinaryProtocol.php');
        include_once(_DAEMON_ROOT.'lib/thrift/transport/TSocketPool.php');
        include_once(_DAEMON_ROOT.'lib/thrift/transport/TBufferedTransport.php');
        include_once(_DAEMON_ROOT.'lib/thrift/packages/Hbase/Hbase.php');

        $this->open();

        //family
        if (!empty($dbConf['singleFamily'])) {
            $this->setSingleFamily($dbConf['singleFamily']);
        }
    }
    /* }}} */

    public function __destruct() {
        $this->close();
    }

    /* {{{ 连db server
     */
    private function open() {
        do {
            if (empty($this->dbServers) || !@is_array($this->dbServers)) {
                throw new Exception("no db servers!");
                break;
            }
            foreach ($this->dbServers as $serverInfo) {
                list($masterHost,$masterPort)=explode(':',$serverInfo);
                $this->dbHosts[]=$masterHost;
                $this->dbPorts[]=$masterPort;
            }
            $this->socket = new TSocketPool($this->dbHosts, $this->dbPorts);
            $this->socket->setSendTimeout($this->sendTimeout);
            $this->socket->setRecvTimeout($this->recvTimeout);
            $this->transport = new TBufferedTransport($this->socket);
            $this->protocol= new TBinaryProtocol($this->transport);
            $this->client = new HbaseClient($this->protocol);
            $this->transport->open();

            //当前连接的host
            $this->connectedHost=$this->socket->getHost();
            $this->connectedPort=$this->socket->getPort();

            _debug("[".__METHOD__."][connected:{$this->connectedHost}({$this->connectedPort})]",_DLV_NOTICE);
        } while(false);
    }
    /* }}} */

    /* {{{ 关闭数据库
     */
    private function close() {
        if (isset($this->transport)) {
            $this->transport->close();
        }
    }
    /* }}} */

    /* {{{ set family
     */
    public function setSingleFamily($family) {
        $ret=false;
        do {
            if (!empty($family)) {
                $this->singleFamily=$family;
            }
            $ret=true;
        } while(false);
        return $ret;
    }
    /* }}} */

    /* {{{ fields=>columns
     */
    private function fields2Columns($fields) {
        foreach ($fields as $field) {
            if ($this->singleFamily=='_custom_') {  //特别设置
                $dbField=$field;
            } else {
                $dbField=$this->singleFamily.":".$field;
            }
            $dbFields[]=$dbField;
            $this->fieldMap[$dbField]=$field;
        }
        return $dbFields;
    }
    /* }}} */

    /* {{{ get,通过rowkey获取信息,以数组返回
     * @param string $table  required
     * @param string $row    required
     * @param array  $fields required
     * @return mixed
     */
    public function iGet($table,$row,$fields) {
        $ret=false;
        try {

            if (empty($fields)) {
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            $tmp=$this->client->getRowWithColumns($table,$row,$dbFields);
            if (is_object($tmp[0])) {
                $ret['key']=$row;
                foreach ($tmp[0]->columns as $column=>$vObj) {
                    $fName=isset($this->fieldMap[$column])?$this->fieldMap[$column]:$column;
                    $ret['item'][$fName]=$vObj->value;
                }
            }
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $ret;
    }
    /* }}} */

    /* {{{ BatchGet, 可同时获取多个rowkey信息
     * @param string $table  required
     * @param array  $rows   required
     * @param array  $fields required
     * @return mixed
     */
    public function iBatchGet($table,$rows,$fields) {
        $ret=false;
        try {
            if (empty($fields)) {
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            $tmp=$this->client->getRowsWithColumns($table,$rows,$dbFields);
            if (is_array($tmp)) {
                foreach ($tmp as $key=>$rValue) {
                    $ret[$key]['key']=$rValue->row;
                    foreach ($rValue->columns as $column=>$vObj) {
                        $fName=isset($this->fieldMap[$column])?$this->fieldMap[$column]:$column;
                        $ret[$key]['item'][$fName]=$vObj->value;
                    }
                }
            }
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $ret;
    }
    /* }}} */

    /* {{{ Put, 写入rowkey(不存在则insert,存在则更新)
     * @param string $table  required
     * @param string $row    required
     * @param array  $data   required   一个多维数组, array('col'=>array('value'=>{value}, 'index'=>{qualifier}))
     * @return mixed
     */
    public function iPut($table,$row,$data) {
        $ret=false;
        try {

            if (empty($data)) {
                throw new Exception("no data!");
            }

            //build mutation
            foreach ($data as $column=>$columnInfo) {
                $mutations[] = new Mutation(
                    array(
                        'column' => $this->singleFamily.':'.$column,
                        'value' => isset($columnInfo['value'])?$columnInfo['value']:'',
                    )
                );
                if ($columnInfo['index']!=false && $columnInfo['value']!=false) {   //索引
                    do {
                        //获取当前的值
                        $idxCurField="index:{$column}:_current_";   //这个作为固定的当前值
                        if ($tmp=$this->client->getRowWithColumns($table,$row,array($idxCurField))) {
                            $oldIdxVal=$tmp[0]->columns[$idxCurField]->value;
                            if ($oldIdxVal==$columnInfo['value']) {  //请求值与当前值一致,不用建立索引了
                                //nothing to do
                                break;
                            }
                            //删除旧的
                            $mutations[] = new Mutation(
                                array(
                                    'isDelete' => 1,
                                    'column' => "index:{$column}:{$oldIdxVal}",
                                    'value' => $oldIdxVal,
                                )
                            );
                        }
                        //一个新的当前值
                        $mutations[] = new Mutation(
                            array(
                                'column' => $idxCurField,
                                'value' => $columnInfo['value'],
                            )
                        );
                        //新索引
                        $mutations[] = new Mutation(
                            array(
                                'column' => "index:{$column}:{$columnInfo['value']}", //之前的index是自动加的
                                'value' => $columnInfo['value'],
                            )
                        );
                    } while(false);
                }
            }

            //insert 
            $this->client->mutateRow($table,$row,$mutations);

            //return true
            $ret=true;  //成功
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $ret;
    }
    /* }}} */

    /* {{{ Delete, 删除rowkey
     * @param string $table  required
     * @param array  $row    required
     * @param array  $fields required  需要删除的字段信息,如果这个参数为null,则删除整个row!
     * @return mixed
     */
    public function iDelete($table,$row,$fields=null) {
        $ret=false;
        try {
            if ($row==false) {
                throw new Exception("no row!");
            }

            if ($fields!==null) {   //删除字段
                $dbFields=$this->fields2Columns($fields);
                $this->client->deleteAll($table,$row,$dbFields);
            } else {    //删除整条row!
                $this->client->deleteAllRow($table,$row);
            }

            $ret=true;
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }

        return $ret;
    }
    /* }}} */
    
    /* {{{ BatchWrite, 可同时写入多个rowkey(字段的更新删除均可,但不可删除整个row)
     * @param string $table       required
     * @param array  $batchRows   required   一个多维数组, array({row} => array('col'=>array('value'=>{value}, 'index'=>{qualifier},'delete'=>{1/0})))
     * @return mixed
     */
    public function iBatchWrite($table,$batchRows) {
        $ret=false;
        try {

            if (empty($batchRows)) {
                throw new Exception("no data!");
            }

            foreach ($batchRows as $row=>$data) {
                //build mutations
                foreach ($data as $column=>$columnInfo) {
                    $mutations[] = new Mutation(
                        array(
                            'isDelete' => (int)$columnInfo['delete'],
                            'column' => $this->singleFamily.':'.$column,
                            'value' => isset($columnInfo['value'])?$columnInfo['value']:'',
                        )
                    );
                    if ($columnInfo['index']!=false && $columnInfo['value']!=false) {   //索引
                        do {
                            //获取当前的值
                            $idxCurField="index:{$column}:_current_";   //这个作为固定的当前值
                            if ($tmp=$this->client->getRowWithColumns($table,$row,array($idxCurField))) {
                                $oldIdxVal=$tmp[0]->columns[$idxCurField]->value;
                                if ($oldIdxVal==$columnInfo['value'] && $columnInfo['delete']==false) {  //请求值与当前值一致,不用建立索引了(且非删除操作)
                                    //nothing to do
                                    break;
                                }
                                //删除旧的
                                $mutations[] = new Mutation(
                                    array(
                                        'isDelete' => 1,
                                        'column' => "index:{$column}:{$oldIdxVal}",
                                        'value' => $oldIdxVal,
                                    )
                                );
                            }
                            //一个新的当前值
                            $mutations[] = new Mutation(
                                array(
                                    'isDelete' => (int)$columnInfo['delete'],
                                    'column' => $idxCurField,
                                    'value' => $columnInfo['value'],
                                )
                            );
                            //新索引
                            $mutations[] = new Mutation(
                                array(
                                    'isDelete' => (int)$columnInfo['delete'],
                                    'column' => "index:{$column}:{$columnInfo['value']}", //之前的index是自动加的
                                    'value' => $columnInfo['value'],
                                )
                            );
                        } while(false);
                    }
                }
                //batch mutation
                $batchMutations[]=new BatchMutation(
                    array(
                        'row' => $row,
                        'mutations' => $mutations,
                    )
                );
                unset($mutations);
            }

            //write
            $this->client->mutateRows($table,$batchMutations);

            //return true
            $ret=true;  //成功
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
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
    public function iScan($table,$fields,$conds=null,$startRow='',$count=50) {
        $ret=false;

        try {
            if (empty($fields)) {
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            //确定最大返回条目
            if ($count>$GLOBALS['maxLimit'] && $GLOBALS['maxLimit']>0) {
                $count=$GLOBALS['maxLimit'];
            }

            if (!empty($conds)) {   //传入了查询条件
                /* {{{ scannerOpenWithScan,失败
                 */
                //$flt = 'DependentColumnFilter("index", "'."{$qualifier}:{$value}".'", false, =, "'.$value.'")';
                //$scan = new TScan(array("filterString" => $flt, 'columns' => $scanFields));
                //if ($scanId=$this->client->scannerOpenWithScan($table,$scan)) {
                //    if (false!=($scanRows=$this->client->scannerGetList($scanId,$count))) {
                //        foreach($scanRows as $sn=>$rowDetail) {
                //            $ret[$sn]['key']=$rowDetail->row;
                //            foreach($rowDetail->columns as $field=>$vObj) {
                //                $ret[$sn]['item'][$field]=$vObj->value;
                //            }
                //        }
                //    }
                //}
                /* }}} */
                foreach($conds as $column=>$value) {
                    if ($this->singleFamily=='_custom_') {  //特别设置,全部由用户传入
                        $condFields[]=$value;
                    } else {
                        $condFields[]="index:{$column}:{$value}";
                    }
                }
                if ($scanId=$this->client->scannerOpen($table,$startRow,$condFields)) {
                    if (false!=($scanRows=$this->client->scannerGetList($scanId,$count))) {
                        foreach($scanRows as $rowDetail) {
                            $find=true;
                            foreach ($condFields as $conField) {
                                if (!isset($rowDetail->columns[$conField])) {
                                    $find=false;
                                    break;
                                }
                            }
                            if ($find===true) {
                                $findRows[]=$rowDetail->row;
                            }
                        }
                    }
                }
                if (!empty($findRows)) {
                    $ret=$this->iBatchGet($table,$findRows,$fields);
                }
            } else {    //没有传入条件,正常openScanner
                if ($scanId=$this->client->scannerOpen($table,$startRow,$dbFields)) {
                    if (false!=($scanRows=$this->client->scannerGetList($scanId,$count))) {
                        foreach($scanRows as $sn=>$rowDetail) {
                            $ret[$sn]['key']=$rowDetail->row;
                            foreach($rowDetail->columns as $field=>$vObj) {
                                $fName=isset($this->fieldMap[$column])?$this->fieldMap[$column]:$column;
                                $ret[$sn]['item'][$fName]=$vObj->value;
                            }
                        }
                    }
                }
            }
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }

        return $ret;
    }
    /* }}} */

    /* {{{ query, 这个应该可以进行范围请求
     */
    public function iQuery($table,$prefix,$fields,$count=1) {
        $ret=false;
        try {

            if (empty($fields)) {
                throw new Exception("no fields!");
            }

            $dbFields=$this->fields2Columns($fields);

            if ($scanId=$this->client->scannerOpenWithPrefix($table,$prefix,$dbFields)) {
                if (false!=($scanRows=$this->client->scannerGetList($scanId,$count))) {
                    foreach($scanRows as $sn=>$rowDetail) {
                        $ret[$sn]['key']=$rowDetail->row;
                        foreach($rowDetail->columns as $field=>$vObj) {
                            $fName=isset($this->fieldMap[$column])?$this->fieldMap[$column]:$column;
                            $ret[$sn]['item'][$fName]=$vObj->value;
                        }
                    }
                }
            }
        } catch (Exception $e) {
            _debug("[".__METHOD__."][Caught Exception:".$e->getMessage()."]",_DLV_ERROR);
        }
        return $ret;
    }
    /* }}} */
}
