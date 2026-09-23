#!/usr/bin/env perl

use strict;
use warnings;
use ZoneMinder;
use JSON;
use feature 'try';

$| = 1;

my @monitors;
logInit();
logSetSignal();

my $dbh = zmDbConnect();

my $majordomo_host = "192.168.0.5";

Info('Zm-MJDM-EventNotification daemon starting');

my $sql = "SELECT * FROM Monitors
  WHERE find_in_set( `Function`, 'Modect,Mocord,Nodect' )".
  ( $Config{ZM_SERVER_ID} ? 'AND ServerId=?' : '' )
  ;

my $sth = $dbh->prepare_cached( $sql )
  or die( "Can't prepare '$sql': ".$dbh->errstr() );

my $res = $sth->execute()
  or die( "Can't execute '$sql': ".$sth->errstr() );

while ( my $monitor = $sth->fetchrow_hashref() ) {
    push( @monitors, $monitor );
}

while (1) {
        foreach my $monitor (@monitors) {
               # Check shared memory ok
               if ( !zmMemVerify( $monitor ) ) {
                 zmMemInvalidate( $monitor );
                 next;
                }

                my $monitorState = zmGetMonitorState($monitor);
		if (defined $monitor->{State}) {
			$monitor->{OldState} = $monitor->{State};
		} else {
			$monitor->{OldState} = 1;
		}
		$monitor->{State} = $monitorState;
		if ($monitor->{OldState} != $monitor->{State}) {
		    processStateChange($monitor);
		}
        }
        sleep 1;
}

sub processStateChange {
    my ($monitor) = @_;
    my $eventId = -1;
    try {
	if ($monitor->{State} == 1 && $monitor->{OldState} == 4) {
	    my $sql2 = "select Id from Events where MonitorId = ".$monitor->{Id}." order by id DESC limit 1";
    	    my $sth2 = $dbh->prepare( $sql2 ) or die( "Can't prepare '$sql': ".$dbh->errstr() );
    	    my $res2 = $sth2->execute() or die( "Can't execute '$sql': ".$sth2->errstr() );
    	    my @row = $sth2->fetchrow_array();
	    $eventId = $row[0];
	}
	my $data = {
	    monitorid	=> $monitor->{Id},
	    monitorName	=> $monitor->{Name},
	    monitorOldState	=> $monitor->{OldState},
	    monitorState	=> $monitor->{State},
	    monitorEventId	=> $eventId,
	    localtime	=> time()
	};
	Info (encode_json($data));
	system("/usr/bin/wget 'http://".$majordomo_host."/api/module/zoneminder/eventnotify?data=".encode_json($data)."' -qO /dev/null");

    }
    catch ($error) {
	Info ("ERROR: $error");
    }
}