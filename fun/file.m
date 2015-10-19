<?php
/*
  +----------------------------------------------------------------------+
  | Name:                                                                |
  +----------------------------------------------------------------------+
  | Comment:                                                             |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Created:2012-05-13 15:58:23                                          |
  +----------------------------------------------------------------------+
  | Last-Modified:2013-08-30 10:19:35                                    |
  +----------------------------------------------------------------------+
*/
/* {{{ system path info 
 */
$GLOBALS['_sys']['mkdir']='/bin/mkdir';
$GLOBALS['_sys']['bzip2']='/usr/bin/bzip2';
$GLOBALS['_sys']['gzip']='/usr/bin/gzip';
$GLOBALS['_sys']['dd']='/bin/dd';
$GLOBALS['_sys']['mv']='/bin/mv';
$GLOBALS['_sys']['bzcat']='/usr/bin/bzcat';
//$GLOBALS['_sys']['gzcat']='/usr/bin/gzcat';
$GLOBALS['_sys']['gzcat']='/usr/bin/gunzip -c'; //很多linux找不到gzcat,用 gunzip -c代替
$GLOBALS['_sys']['tar']='/bin/tar';
$GLOBALS['_sys']['scp']='/usr/bin/scp';
$GLOBALS['_sys']['ssh']='/usr/bin/ssh';
$GLOBALS['_sys']['cp']='/bin/cp';
$GLOBALS['_sys']['rm']='/bin/rm';
$GLOBALS['_sys']['rsync']='/usr/bin/rsync';
/* }}} */

/* {{{ _makeDir
 * 建立文件夹
 */
function _makeDir($path,$mode="0755",$depth=0,$type='d') {
    $input_type=empty($type)?'d':strtolower($type);
    $path=($input_type==='d')?$path:dirname($path);
    $depth--;
    $subpath=dirname($path);
    if (!file_exists($path)) {
        if ($depth>0 && (!empty($subpath) || $subpath!='.')) {
            _makeDir($subpath,$mode,$depth);
        }
        @exec("{$GLOBALS['_sys']['mkdir']} -p -m $mode $path");
    } elseif (is_dir($path)) {
        return true;
    } else {
        return false;
    }
}
/* }}} */

/* {{{ _findAllFiles
 * Recursive functions
 */
function _findAllFiles($dir,$fileExt=null,$depth=1,$check=true,$max=0) {
    $ret=array();
    if ($root = scandir($dir)) {
        foreach($root as $value) { 
            if($value === '.' || $value === '..') {
                continue;
            } 
            if(is_file("$dir/$value")) {
                $info=pathinfo($value);
                if ((!empty($fileExt) && $info['extension']==$fileExt) || (empty($fileExt) && @in_array($info['extension'],array('tgz','tbz2')))) {
                    $file="$dir/$value";
                    $stat=0;
                    if ($check==true) {
                        $checkCmd=($info['extension']=='tbz2')?$GLOBALS['_sys']['bzip2']:$GLOBALS['_sys']['gzip'];
                        @system("$checkCmd -t $file 2>> /dev/null",$stat);
                    }
                    if ($stat==0) {
                        $ret[]="$dir/$value";
                    }
                }
                if ($max>0 && count($ret)>=$max) {
                    break;
                }
                continue;
            }
            if (($depth-1)>0) { //挖掘深度
                foreach(_findAllFiles("$dir/$value",$fileExt,$depth-1,$check,$max-count($max)) as $value) { 
                    $ret[]=$value; 
                }
            }
        }
    }
    return $ret; 
}
/* }}} */

/* {{{ _findBadFiles
 */
function _findBadFiles($dir,$fileExt='tbz2',$timeout=7200) {
    $ret=array();
    $root = scandir($dir); 
    foreach($root as $value) { 
        if($value === '.' || $value === '..') {
            continue;
        } 
        $file="$dir/$value";
        if(is_file($file)) {
            if (!empty($fileExt)) { //需要判断后缀名
                $info=pathinfo($value);
                if ($info['extension']==$fileExt) {
                    $checkCmd=($fileExt=='tbz2')?$GLOBALS['_sys']['bzip2']:$GLOBALS['_sys']['gzip'];
                    @system("$checkCmd -t $file 2>> /dev/null",$stat);
                    if ($stat!=0) {
                        $fileCreateTime=@filemtime($file);
                        if ($timeout<=abs($GLOBALS['currentTime']-$fileCreateTime)) {   //解压失败,并且创建时间超过2小时
                            $ret[]=$file;
                        }
                    }
                }
            }
            continue;
        }
    } 
    return $ret; 
}
/* }}} */

/* {{{ buildFile
 */
function _buildFile($file,$filesize) {
    system("{$GLOBALS['_sys']['dd']} if=/dev/zero of=$file bs=$filesize count=1 2>> /dev/null",$build_stat);
    return $build_stat;
}
/* }}} */

/* {{{ _getLogInfo
 * 获取需要读取日志文件的路径以及位置
 * 读取日志的类型为文本格式，rotate可支持多种类型
 */
function _getLogInfo($logFile,$lastOff,$lastINode,$rotateDetail=null) {
    $ret=false;

    do {
        if (!file_exists($logFile)) {
            _debug("[".__FUNCTION__."][$filename][NOT_FOUND]",_DLV_ERROR);
            break;
        }

        $ret=array(
            'file' => $logFile,
            'inode'  => 0,
            'offset' => (int)$lastOff,
            'read' => false,  //默认不读取
        );

        //log inode 信息
        $logINode=fileinode($logFile);
        //日志文件信息
        $logSize=filesize($logFile);

        if (empty($lastINode)) {    //如果inode为空,就当作第一次读取
            $ret['inode']=$logINode;
            $ret['read']=$logSize>0?true:false;
            _debug("[".__FUNCTION__."][file:{$ret['file']}][inode:{$ret['inode']}][offset:0][first_read]",_DLV_NOTICE);
            break;
        }

        if ($lastINode==$logINode) {    //inode相同,说明还是同一个文件
            $ret['inode']=$logINode;
            if ($lastOff>=$logSize) {   //无新内容,或者内容被删掉了?
                $ret['offset']=$logSize;
            } else {    //上一次读取之后,有了新内容
                $ret['read']=true;
            }
            break;
        } else {    //不是当前文件,需要之前的文件
            $ret['read']=true;  //如果没找到旧文件,则直接读取当前文件
            $ret['offset']=0;
            if (empty($rotateDetail)) { //没有rotateDetail,按照默认情况来
                $rotateDetail=array(
                    'type' => 'syslog',
                );
            }
            for ($i=0;$i<4;$i++) {  //最多找三个rotate文件
                switch ($rotateDetail['type']) {
                case 'cronolog':
                    $oldLogFile=date($rotateDetail['format'],$rotateDetail['ts']-3600*($i+1));  //按小时rorate
                    break;
                default:
                    $oldLogFile=$logFile.'.'.$i;
                    break;
                }
                if (!file_exists($oldLogFile)) {    //找不到文件了,终止
                    break;
                }
                $oldSize=filesize($oldLogFile);
                if ($oldSize<=0) {  //没有内容,跳过
                    continue;
                }
                $oldINode=fileinode($oldLogFile);
                if ($oldINode==$lastINode) {    //找到文件
                    if ($lastOff<$oldSize) {    //有新内容,读
                        $ret['file']=$oldLogFile;
                        $ret['inode']=$oldINode;
                        $ret['offset']=(int)$lastOff;
                    }
                    //终止循环
                    break;
                }

                //当前文件不匹配,如果之后的循环找不到,则从当前文件开始读
                $ret['file']=$oldLogFile;
                $ret['inode']=$oldINode;
            }
        }
    } while(false);

    return $ret;
}
/* }}} */

/* {{{ _moveFiles
 */
function _moveFiles($files,$path) {
    $ret=false;

    do {
        if (empty($files)) {
            break;
        }
        if (!is_dir($path)) {
            break;
        }
        foreach ($files as $file) {
            if (is_file($file)) {
                $moveFiles[]=$file;
            } else {
                $failFiles[]=$file;
            }
        }

        if (!empty($moveFiles)) {
            @exec("{$GLOBALS['_sys']['mv']} -f ".implode(' ',$moveFiles)." {$path}",$arrLines,$stat);
        } else {
            _notice("[success: %s][failed: %s][to: %s]",implode(',',$moveFiles),implode(',',$failFiles),$path);
        }

        $ret=($stat==0)?true:false;

    } while(false);

    return $ret;
}
/* }}} */

/* {{{ _transferFile 
 */
function _transferFile($file,$path,$host=null,$port=null,$user=null,$bak_dir=null,$retry_dir=null,$key=null) {
    $ret=false;
    if (file_exists($file) && !empty($path)) {
        if (!empty($host)) {
            //host不为空,说明是ssh方式
            if (file_exists($GLOBALS['_sys']['rsync'])) {
                if (empty($bak_dir)) {  //不需要备份
                    $removeOps="--remove-source-files";
                }
                if (!empty($key) && file_exists($key)) {
                    $keyCmdStr="-i {$key}";
                }
                $cmd="{$GLOBALS['_sys']['rsync']} -az -e '{$GLOBALS['_sys']['ssh']} -p {$port} {$keyCmdStr} -o StrictHostKeyChecking=no' {$removeOps} --timeout=20 {$file} {$user}@{$host}:{$path} 2>>/dev/null";
            } else {
                $cmd="{$GLOBALS['_sys']['scp']} -P {$port} {$keyCmdStr} -o StrictHostKeyChecking=no -o ConnectTimeout=20 {$file} {$user}@{$host}:{$path} 2>>/dev/null";
            }
        } else {
            //local
            _makeDir($path,"0755",0,'d');
            $cmd="{$GLOBALS['_sys']['cp']} {$file} {$path}";
        }
        _notice("[%s][command: %s]",__FUNCTION__, $cmd);
        system($cmd,$trans_stat);
        if (file_exists($file)) {
            if ($trans_stat===0) {
                if (!empty($bak_dir)) {
                    if (!file_exists($bak_dir)) {
                        _makeDir($bak_dir,"0755",0,'d');
                    }
                    @exec("{$GLOBALS['_sys']['mv']} {$file} {$bak_dir}"); //backup
                } else {
                    //无需备份,删除
                    @exec("{$GLOBALS['_sys']['rm']} -f {$file}");
                }
                $ret=true;
            } elseif (!empty($retry_dir)) {
                if (!file_exists($retry_dir)) {
                    _makeDir($retry_dir,"0755",0,'d');
                }
                @exec("{$GLOBALS['_sys']['mv']} {$file} {$retry_dir}"); //retry
            //} elseif (!empty($bak_dir) && file_exists($bak_dir)) {
            //    exec("{$GLOBALS['_sys']['mv']} {$file} {$bak_dir}"); //backup
            }
        }
    }
    return $ret;
}
/* }}} */

/* {{{ _package
 */
function _package($files,$tarball=null,$type='j') {
    $ret=false;
    do {
        if (empty($files)) {
            break;
        }
        if (empty($tarball)) {
            if (count((array)$files)>1) {
                break;
            } else {
                $tmpArr=(array)$files;
                $tmp=pathinfo(reset($tmpArr));
                $tarName=$tmp['filename'];
                $tarball=$type=='j'?"{$tmp['filename']}.tbz2":"{$tmp['filename']}.tgz";
            }
        }
        $files=(array)$files;
        foreach ($files as $key=>$file) {
            if (!file_exists($file)) {
                unset($files[$key]);
            }
        }
        if (empty($files)) {
            break;
        }
        system("{$GLOBALS['_sys']['tar']} c{$type}f {$tarball} ".implode(' ',(array)$files)." 2>>/dev/null",$tarStat);
        if ($tarStat==0) {
            exec("{$GLOBALS['_sys']['rm']} -f ".implode(' ',(array)$files));
            $ret=$tarball;
        } else {
            $ret=false;
        }
    } while(false);
    return $ret;
}
/* }}} */

/* {{{ _updateTdb
 */
function _updateTdb($file_fullpath,$file_content) {
    if($fp=@fopen($file_fullpath,"wb")){
        fputs($fp,$file_content);
        ftruncate($fp,strlen($file_content));
        fclose($fp);
        return TRUE;
    } else {
        return FALSE;
    }
}
/* }}} */

/* {{{ function _getStatus($file)
 * 从文件中读取状态
 */
function _getStatus($file) {
    $rt=false;

    if (file_exists($file) && false!=($ss=trim(file_get_contents($file)))) {
        if (false!=($rt=json_decode($ss,true))) {
        } else {
            $rt=$ss;
        }
    }

    return $rt;
}

/* }}} */

/* {{{ function _saveStatus($status,$file)
 *
 */
function _saveStatus($status,$file) {
    $rt=false;

    try {
        if (is_array($status)) {
            $status['_ts_']=time();
            $status=json_encode($status);
        }
        _updateTdb($file,$status);
    } catch (Exception $e) {
        _error("Exception: %s", $e->getMessage());
    }

    return $rt;
}

/* }}} */


