#! /bin/bash

# This is the install script for GUV. 

version=002

set -e

#CS: check for ada compiler, gcc, make, ...


dest_conf_dir=$HOME/.guv
dest_data_dir=$HOME/guv

echo "GUV installer version" $version

procedure_operator_confirmation()
	{
	echo -n "proceed ? (y/n): "
	read key
	echo
	if [ ! $key = "y" ] 
		then
			echo "aborted by operator"
			exit 1
	fi
	}

procedure_make()
	{
	target=$1
	echo "-" $target
	cd src/$target # change into source dir
	make clean # clean up
	make # compile
	make install # install
	make clean # clean up
	cd - # change back to origin dir
	}

# If configuration already exists, leave it as it is.
# Otherwise create it with a base configuration for evaluation.
[ ! -e $dest_conf_dir ] && 
	{
	echo "creating hidden configuration directory" $dest_conf_dir "..."
	cp -R conf/guv $dest_conf_dir
	}
	#CS: ask user if configuration directory should be updated.

# If database directory already exists, leave it as it is.
# Otherwise create it with a dummy database for evaluation.
[ ! -e $dest_data_dir ] && 
	{
	echo "creating database directory" $dest_data_dir "..."
	cp -R examples $dest_data_dir
	}


	
echo "compiling and installing ..."
set +e

procedure_make guv

echo "installation complete"
echo "now edit settings in" $dest_conf_dir/guv.conf
exit
