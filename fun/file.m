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
$GLOBALS['_sys']['gzcat']='/usr/bin/gzcat';
$GLOBALS['_sys']['tar']='/usr/bin/tar';
$GLOBALS['_sys']['scp']='/usr/bin/scp';
$GLOBALS['_sys']['cp']='/bin/cp';
$GLOBALS['_sys']['rm']='/bin/rm';
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
function _findAllFiles($dir,$fileExt='tbz2',$depth=1,$check=true,$max=0) {
    $ret=array();
    if ($root = scandir($dir)) {
        foreach($root as $value) { 
            if($value === '.' || $value === '..') {
                continue;
            } 
            if(is_file("$dir/$value")) {
                if (!empty($fileExt)) { //需要判断后缀名
                    $info=pathinfo($value);
                    if ($info['extension']==$fileExt) {
                        $file="$dir/$value";
                        $stat=0;
                        if ($check==true) {
                            $checkCmd=($fileExt=='tbz2')?$GLOBALS['_sys']['bzip2']:$GLOBALS['_sys']['gzip'];
                            @system("$checkCmd -t $file 2>> /dev/null",$stat);
                        }
                        if ($stat==0) {
                            $ret[]="$dir/$value";
                        }
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
            _debug("[success:".implode(',',$moveFiles)."][failed:".implode(',',$failFiles)."][to:{$path}]");
        } else {
            _debug("[success:".implode(',',$moveFiles)."][failed:".implode(',',$failFiles)."][to:{$path}]",_DLV_WARNING);
        }

        $ret=($stat==0)?true:false;

    } while(false);

    return $ret;
}
/* }}} */

/* {{{ _transferFile 
 */
function _transferFile($file,$path,$host=null,$port=null,$user=null,$bak_dir=null,$retry_dir=null) {
    $ret=false;
    if (file_exists($file) && !empty($path)) {
        if (!empty($host)) {
            //host不为空,说明是ssh方式
            $cmd="{$GLOBALS['_sys']['scp']} -P {$port} -o StrictHostKeyChecking=no -o ConnectTimeout=20 {$file} {$user}@{$host}:{$path} 2>>/dev/null";
        } else {
            //local
            _makeDir($path,"0755",0,'d');
            $cmd="{$GLOBALS['_sys']['cp']} {$file} {$path}";
        }
        _debug("[".__FUNCTION__."][command:{$cmd}]",_DLV_NOTICE);
        system($cmd,$trans_stat);
        if ($trans_stat===0) {
            if (!empty($bak_dir)) {
                if (!file_exists($bak_dir)) {
                    _makeDir($bak_dir,"0755",0,'d');
                }
                exec("{$GLOBALS['_sys']['mv']} {$file} {$bak_dir}"); //backup
            //} else {
            //    exec("{$GLOBALS['_sys']['rm']} -f {$file}");
            }
            $ret=true;
        } elseif (!empty($retry_dir)) {
            if (!file_exists($retry_dir)) {
                _makeDir($retry_dir,"0755",0,'d');
            }
            exec("{$GLOBALS['_sys']['mv']} {$file} {$retry_dir}"); //retry
        } elseif (!empty($bak_dir) && file_exists($bak_dir)) {
            exec("{$GLOBALS['_sys']['mv']} {$file} {$bak_dir}"); //backup
        //} else {
        //    exec("{$GLOBALS['_sys']['rm']} -f {$file}");
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
