#! /usr/bin/env nix-shell
#! nix-shell release-benchmarks.nix -i bash
#
# This script runs the lwAFTR release benchmarks
#
# Set SNABB_PCI0 to SNABB_PCI7 when calling

# directory this script lives in
# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR=$(dirname "$(readlink -f "$0")")

# path to snabb executable
SNABB=$DIR/../../../../snabb

# config files & pcap dataset paths
FROM_B4_PCAP=$dataset/from-b4-test.pcap
FROM_INET_PCAP=$dataset/from-inet-test.pcap
FROM_INET_AND_B4_PCAP=$dataset/from-inet-and-b4-test.pcap
CONFIGS=$dataset/*.conf

# make sure lwaftr gets shut down even on interrupt
function teardown {
    [[ -n $lwaftr_pid ]] && kill $lwaftr_pid
    [[ -n $lt_pid ]] && kill $lt_pid
    [[ -n $lt_pid2 ]] && kill $lt_pid2
}

trap teardown INT TERM

TMPDIR=`mktemp -d`

# called with benchmark name, config path, args for lwAFTR, args for loadtest
# optionally args of the second loadtest
function run_benchmark {
    name="$1"
    config="$2"
    lwaftr_args="$3"
    loadtest_args="$4"
    loadtest2_args="$5"

    $SNABB lwaftr run --cpu 11 --name lwaftr --conf \
           $dataset/$config $lwaftr_args > /dev/null &
    lwaftr_pid=$!

    # wait briefly to let lwaftr start up
    sleep 1

    log=`mktemp -p $TMPDIR`
    echo ">> Running loadtest: $name (log: $log)"
    $SNABB loadtest find-limit $loadtest_args > $log &
    lt_pid=$!

    if [ ! -z "$loadtest2_args" ]; then
        log2=`mktemp -p $TMPDIR`
        echo ">> Running loadtest 2: $name (log: $log2)"
        $SNABB loadtest find-limit $loadtest2_args > $log2 &
        lt_pid2=$!
    fi

    wait $lt_pid
    status=$?
    if [ ! -z "$loadtest2_args" ]; then
        wait $lt_pid2
        status2=$?
    fi

    kill $lwaftr_pid

    if [ $status -eq 0 ]; then
        echo ">> Success: $(tail -n 1 $log)"
    else
        echo ">> Failed: $(tail -n 1 $log)"
        exit $status
    fi
    if [ ! -z "$loadtest2_args" ]; then
        if [ $status2 -eq 0 ]; then
            echo ">> Success: $(tail -n 1 $log2)"
        else
            echo ">> Failed: $(tail -n 1 $log2)"
            exit $status
        fi
    fi
}

# first ensure all configs are compiled
echo ">> Compiling configurations (may take a while)"
for conf in $CONFIGS
do
    $SNABB lwaftr compile-configuration $conf
done

run_benchmark "1 instance, 2 NIC interface" \
              "lwaftr.conf" \
              "--v4 $SNABB_PCI0 --v6 $SNABB_PCI2" \
              "$FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI1 \
               $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI3"

run_benchmark "1 instance, 2 NIC interfaces (from config)" \
              "lwaftr2.conf" \
              "--v4 $SNABB_PCI0 --v6 $SNABB_PCI2" \
              "$FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI1 \
               $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI3"

run_benchmark "1 instance, 1 NIC (on a stick)" \
              "lwaftr.conf" \
              "--on-a-stick $SNABB_PCI0" \
              "$FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1"

run_benchmark "1 instance, 1 NIC (on-a-stick, from config file)" \
              "lwaftr3.conf" \
              "" \
              "$FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1"

run_benchmark "2 instances, 2 NICs (from config)" \
              "lwaftr4.conf" \
              "" \
              "--cpu 2 $FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI1 \
               $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI3" \
              "--cpu 3 $FROM_INET_PCAP NIC0 NIC1 $SNABB_PCI5 \
               $FROM_B4_PCAP NIC1 NIC0 $SNABB_PCI7"

run_benchmark "2 instances, 1 NIC (on a stick, from config)" \
              "lwaftr5.conf" \
              "" \
              "--cpu 2 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1" \
              "--cpu 3 $FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI5"

run_benchmark "1 instance, 1 NIC, 2 queues" \
              "lwaftr6.conf" \
              "" \
              "$FROM_INET_AND_B4_PCAP NIC0 NIC0 $SNABB_PCI1"

# cleanup
rm -r $TMPDIR
