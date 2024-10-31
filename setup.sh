#!/bin/bash
set -x

touch /tmp/init.log

exec > /tmp/init.log 2>&1

# c220g5 specific
disk_dev=/dev/sda4
work_dir=/tip
chipyard_repo=https://github.com/ucb-bar/chipyard.git
boom_repo=https://github.com/songmuhan/tip.git
conda=$work_dir/miniforge3/bin/conda
benchmarks=/tip/chipyard/.conda-env/riscv-tools/riscv64-unknown-elf/share/riscv-tests/benchmarks/

function setup_workdir() {
    echo "Formatting $disk_dev, mounting to $work_dir"

    sudo mkfs.ext4 $disk_dev || { echo "$disk_dev has been formatted"; }

    sudo mkdir $work_dir || { echo "$work_dir exsits"; }

    sudo mount $disk_dev $work_dir || { echo "Mounting failed"; }
    
    echo "Mounting successful, changing current work dir"
    cd $work_dir || { echo "can not cd into $work_dir"; exit 1; }

    sudo chmod -R a+rw $work_dir

    echo "$(pwd)"

}
function setup_miniforge3() {
    echo "Installing Miniforge3"
    curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
    bash Miniforge3-Linux-x86_64.sh -b -p $work_dir/miniforge3/ || { echo "Miniforge3 installation failed"; exit 1; }
    echo "$(which conda)"
    echo "Miniforge3 installed successfully"
}

function setup_conda() {
    echo "setup conda ...."
    $conda install -n base conda-lock=1.4 -y
    source $work_dir/miniforge3/etc/profile.d/conda.sh
    $conda env list
    source $work_dir/miniforge3/bin/activate base

}

function setup_chipyard(){
    # get chipyard
    git clone https://github.com/ucb-bar/chipyard.git $work_dir/chipyard
    cd $work_dir/chipyard
    # stick to 1.10.0
    git checkout 1.10.0

    # init
    export PATH="$PATH:$work_dir/miniforge3/bin"
    echo "$PATH"
    source build-setup.sh riscv-tools -s 6 -s 7 -s 8 -s 9

    # replace boom with mine
    git config --global --add safe.directory /tip/chipyard
    rm -rf $work_dir/chipyard/generators/boom
    git clone $boom_repo $work_dir/chipyard/generators/boom
    cd $work_dir/chipyard/generators/boom
    git switch deg
    
    sudo chmod a+rw **/*.scala
    
    $conda env list
    source $work_dir/chipyard/env.sh
    $conda env list
}

function test_all_env() {
    cd $work_dir/chipyard/sims/verilator
    # run qsort to make sure all environment is ready
    make -j CONFIG=MediumBoomConfig run-binary BINARY=$benchmarks/qsort.riscv LOADMEM=1 
}

function setup_utils() {
   sudo apt-get update
   sudo apt-get --yes install neovim tmux htop autojump ripgrep
   # conda env, autojump, set default editor to nvim
   sudo sh -c 'echo "export PATH=\"/tip/miniforge3/bin:\$PATH\"" >> /root/.bashrc && \
   echo ". /usr/share/autojump/autojump.sh" >> /root/.bashrc && \
   echo "export VISUAL=nvim" >> /root/.bashrc && \
   echo "export EDITOR=\"\$VISUAL\"" >> /root/.bashrc'
}

function setup_git_info() {
    # directly write the following content into /root/.gitconfig
    sudo tee /root/.gitconfig > /dev/null << 'EOF'
[safe]
        directory = /tip/chipyard/generators/boom
[user]
        name = Muhan Song
        email = songmuhan99@gmail.com
[credential]
        helper = cache
EOF

}

function add_conda_initialize() {
    sudo tee -a /root/.bashrc > /dev/null << 'EOF'
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/tip/miniforge3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/tip/miniforge3/etc/profile.d/conda.sh" ]; then
        . "/tip/miniforge3/etc/profile.d/conda.sh"
    else
        export PATH="/tip/miniforge3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
EOF
}


function setup_pk(){
    git clone https://github.com/riscv-software-src/riscv-pk.git /tmp/riscv-pk
    mkdir /tmp/riscv-pk/build && cd /tmp/riscv-pk/build
    ../configure --prefix=$RISCV --host=riscv64-unknown-elf
    make -j
    make install -j
}

function add_tea_required_tlb_fileds(){
    # TEA need add some fileds in tlb, which is in rocket-chip
    # refer this commit:
    # https://github.com/EECS-NTNU/rocket-chip/commit/a6540f0472c141f4636ef31374f9266908ffccd0
    tlb_file=/tip/chipyard/generators/rocket-chip/src/main/scala/rocket/TLB.scala
    sed -i '89i\
    val tlb_miss = Bool()\
    val ptw_fired = Bool()\
    ' $tlb_file
    sed -i '651i\
    io.resp.tlb_miss := usingVM.B && tlb_miss\
    io.resp.ptw_fired := usingVM.B && io.req.fire && tlb_miss\
    ' $tlb_file
}

 

setup_workdir
setup_miniforge3
setup_conda
setup_chipyard
setup_utils
setup_git_info
add_tea_required_tlb_fileds
test_all_env
add_conda_initialize
