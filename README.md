# pg_rman
pg_rman自动安装自动备份脚本，自动化操作  
pg_rman is installed locally, postgresql is installed in k8s or docker 
## 文档说明
### （1）pgrman_conf.json
自定义pgrman的配置文件，包含主机IP、pgdata路径、备份路径(建议pgdata和备份路径在不同磁盘下)、端口、pg用户名和密码。
### （2）create.sh
初始化脚本，里面配置了pg_rman的相关参数，并且创建了pg_arch和pg_log目录。 
### （3）pgrman_install.sh 
pg_rman自动安装脚本，需要提前准备pgrman和pg-libs的rpm安装包。最后设置crontab定时任务调用backup.sh脚本进行自动备份 
### （4）pgrman_backup.sh
 自动备份脚本，并且打印日志。

## pgrman_conf.json
```
{  
    "host":"192.168.119.83",  
    "It is recommended that the data directory and backup directory be placed on different disks !!!":"",  
    "data_path":"/home/pgdata",  
    "backup_path":"/home/pgbackup",  
    "port": "5434",  
    "user": "postgres",  
    "password": "postgres"  
}
```A
