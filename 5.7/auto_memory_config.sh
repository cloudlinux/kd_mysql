#!/bin/bash
# This script create configuration with automatically configured memory
# allocation. It is useful only when container with MySQL is limited by memory
# usage.
# We set here settings so, that MySQL server will take so much memory
# of available that it will not be OMM killed, and will increase performance
# if memory limit was increased.
# Script accepts one positional argument - engine type.
# Set it to 'innodb' to auto allocate memory for innodb engine.
# Set it to 'myisam' to auto allocate memory for MyISAM engine.
# Minimal memory needed for MySQL container with INNODB configuration is
# 256Mb.


ENGINE="$1"

if [ "$ENGINE" != innodb ] && [ "$ENGINE" != myisam ]; then
    echo "Unsupported engine. Exit"
    exit 1
fi

CONFIG_FILE=/etc/mysql/conf.d/auto_memory_config.cnf
MEM_STAT_FILE=/sys/fs/cgroup/memory/memory.stat
TOTAL_MEMORY=$(grep hierarchical_memory_limit $MEM_STAT_FILE|cut -d ' ' -f 2)

if ! [[ "$TOTAL_MEMORY" =~ ^[0-9]+$ ]] ; then
    echo "Failed to detect available memory size."
    exit 1
fi

# Here are some groups for memory configurations, depending of available memory
MEMORY_LIMIT_256M=$((256 * 1024 * 1024))
MEMORY_LIMIT_512M=$((512 * 1024 * 1024))
MEMORY_LIMIT_1G=$((1024 * 1024 * 1024))


# Possible minimal settings
innodb_buffer_pool_size=$((5 * 1024 * 1024))
innodb_log_buffer_size=$((256 * 1024))
key_buffer_size=8

query_cache_size=0
innodb_ft_cache_size=1600000
innodb_ft_total_cache_size=32000000
innodb_log_files_in_group=2
innodb_log_file_size=$((4 * 1024 * 1024))

thread_stack=131072
sort_buffer_size=$((32 * 1024))
read_buffer_size=8200
read_rnd_buffer_size=8200
max_heap_table_size=$((1 * 1024))
tmp_table_size=$((1 * 1024))
bulk_insert_buffer_size=0
join_buffer_size=128
net_buffer_length=1024
innodb_sort_buffer_size=$((64 * 1024))

binlog_cache_size=$((4 * 1024))
binlog_stmt_cache_size=$((4 * 1024))

performance_schema=OFF

# Assume one additional connection for every 25mb available memory
MAX_CONNECTION_DIVIDER=$((1024 * 1024 * 25))

if (( $TOTAL_MEMORY <= $MEMORY_LIMIT_512M )); then
    max_connections=10
    
    if (( $TOTAL_MEMORY > $MEMORY_LIMIT_256M )); then
        TO_ALLOCATE=$(($TOTAL_MEMORY - $MEMORY_LIMIT_256M))
        max_connections=$(($max_connections + $TO_ALLOCATE / $MAX_CONNECTION_DIVIDER))
        if [ "$ENGINE" = innodb ]; then
            innodb_buffer_pool_size=$(( $innodb_buffer_pool_size + $TO_ALLOCATE / 2 ))
            innodb_log_buffer_size=$((4 * 1024 * 1024))
        elif [ "$ENGINE" = myisam ]; then
            key_buffer_size=$(( $key_buffer_size + $TO_ALLOCATE / 4 ))
        fi
    fi

elif (( $TOTAL_MEMORY < $MEMORY_LIMIT_1G )); then

    TO_ALLOCATE=$(($TOTAL_MEMORY - $MEMORY_LIMIT_512M))
    if [ "$ENGINE" = innodb ]; then
      innodb_buffer_pool_size=$((256 * 1024 * 1024 + $TO_ALLOCATE / 2))
      innodb_log_buffer_size=$((4 * 1024 * 1024))
    elif [ "$ENGINE" = myisam ]; then
        key_buffer_size=$(( 256 * 1024 * 1024 + $TO_ALLOCATE / 4 ))
    fi
    max_connections=$((20 + $TO_ALLOCATE / $MAX_CONNECTION_DIVIDER))

    sort_buffer_size=$((1024 * 1024))
    read_buffer_size=$((32 * 1024))
    read_rnd_buffer_size=$((32 * 1024))
    max_heap_table_size=$((1024 * 1024))
    tmp_table_size=$((1024 * 1024))
    join_buffer_size=1024
    net_buffer_length=$((4 * 1024))
    innodb_sort_buffer_size=$((1024 * 1024))

else # All that is greater than 1G of available memory

    TO_ALLOCATE=$(($TOTAL_MEMORY - $MEMORY_LIMIT_1G))
    if [ "$ENGINE" = innodb ]; then
        innodb_buffer_pool_size=$((512 * 1024 * 1024 + $TO_ALLOCATE / 2 ))
        innodb_log_buffer_size=$((32 * 1024 * 1024 ))
    elif [ "$ENGINE" = myisam ]; then
        key_buffer_size=$(( 256 * 1024 * 1024 + $TO_ALLOCATE / 4 ))
    fi
    max_connections=$((40 + $TO_ALLOCATE / $MAX_CONNECTION_DIVIDER))
    query_cache_size=1048576
    innodb_ft_cache_size=8000000
    innodb_ft_total_cache_size=640000000
    innodb_log_files_in_group=2
    innodb_log_file_size=$((64 * 1024 * 1024))

    thread_stack=262144
    sort_buffer_size=$((2 * 1024 * 1024))
    read_buffer_size=$((128 * 1024))
    read_rnd_buffer_size=$((256 * 1024))
    max_heap_table_size=$((16 * 1024 * 1024))
    tmp_table_size=$((16 * 1024 * 1024))
    bulk_insert_buffer_size=$((8 * 1024 * 1024))
    join_buffer_size=$((128 * 1024))
    net_buffer_length=$((16 * 1024))
    innodb_sort_buffer_size=$((1024 * 1024))

    binlog_cache_size=$((32 * 1024))
    binlog_stmt_cache_size=$((32 * 1024))

    performance_schema=ON
fi



cat > $CONFIG_FILE << EOF
[mysqld]
# Auto configuration of memory usage for engine "$ENGINE"
# Total memory detected: $TOTAL_MEMORY
innodb_buffer_pool_size=$innodb_buffer_pool_size
innodb_log_buffer_size=$innodb_log_buffer_size
query_cache_size=$query_cache_size
max_connections=$max_connections
key_buffer_size=$key_buffer_size
innodb_ft_cache_size=$innodb_ft_cache_size
innodb_ft_total_cache_size=$innodb_ft_total_cache_size
innodb_log_files_in_group=$innodb_log_files_in_group
innodb_log_file_size=$innodb_log_file_size

thread_stack=$thread_stack
sort_buffer_size=$sort_buffer_size
read_buffer_size=$read_buffer_size
read_rnd_buffer_size=$read_rnd_buffer_size
max_heap_table_size=$max_heap_table_size
tmp_table_size=$tmp_table_size
bulk_insert_buffer_size=$bulk_insert_buffer_size
join_buffer_size=$join_buffer_size
net_buffer_length=$net_buffer_length
innodb_sort_buffer_size=$innodb_sort_buffer_size

binlog_cache_size=$binlog_cache_size
binlog_stmt_cache_size=$binlog_stmt_cache_size

performance_schema=$performance_schema

innodb_flush_method            = O_DIRECT
innodb_flush_log_at_trx_commit = 1
innodb_file_per_table          = 1
EOF
