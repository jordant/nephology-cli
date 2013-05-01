#!/usr/bin/perl
# Nephology CLI client
# **** Very Alpha, use at your own risk ****
# Jordan Tardif < jordan@dreamhost.com > 04302013

use DBI;
use Text::Table;
use Getopt::Long;
use JSON::XS;

# get command line flags
my %opt = ();
GetOptions (
            \%opt, 'status_id=i', 'caste_id=i', "boot_mac=s", "domain=s",
            "primary_ip=s", "hostname=s", "asset_tag=i", "sort_by=s",
            "update", "caste-show=i", "config-file=s"
            );

$opt{'sort_by'} = "asset_tag" unless ($opt{'sort_by'}); #default sort 
$opt{'config-file'} = "neph.json" unless ($opt{'config-file'}); #default config

my $config = &GetConfig;
my $db = &GetDB or die "Cannot connect to database, check your $opt{'config-file'}\n";

my $Nodes = &GetNodes;
if ($opt{'update'} && scalar(%{$Nodes}) > 1) {
    print "I refuse to update more then one node at a time, AND you were trying to update ".scalar(%{$Nodes})."\n";
    die;
} else {
    my ($nodeid) = %{$Nodes};
    my $Node = $Nodes->{$nodeid};
    &Update($Node);
    $Nodes = &GetNodes; # refresh node
}

my $tbn = Text::Table->new(
		"Boot MAC", "Primary IP", "AssetTag", "Nodename", "Domain", "Node Status", "Caste ID"
);

NODE: for my $nodeid (sort {%$Nodes->{$a}->{$opt{'sort_by'}} <=> %$Nodes->{$b}->{$opt{'sort_by'}}} keys %{$Nodes}) {
	my $Node = $Nodes->{$nodeid};
	my $NodeStatus = &NodeStatus($Node);
	$tbn->load(
		[$Node->{'boot_mac'}, $Node->{'primary_ip'}, $Node->{'asset_tag'}, $Node->{'hostname'}, $Node->{'domain'}, $NodeStatus->{'template'}." ( $NodeStatus->{'status_id'} )", $Node->{'caste_id'}]
	);
}

print $tbn."\n";

sub GetConfig {
    # Load config file AND DB hANDle
    my $json = new JSON::XS;
    open(FILE, $opt{'config-file'}) or die "Can't read file 'filename' [$!]\n";  
    my $content = join("", <FILE>); 
    close (FILE);  
    return decode_json($content);
}


sub Update {
    my $Node = shift || return;
    my @set = ();
    my @allowed_update = qw (status_id caste_id domain hostname primary_ip boot_mac admin_user admin_password ipmi_user ipmi_password);
    for $allow (@allowed_update) {
        next unless $opt{$allow};
        push(@set,join("=",($allow,$opt{$allow})));
    }
    if (scalar(@set)) { 
        $db->do("UPDATE node SET ".join(",",@set)." WHERE id='$Node->{'id'}'");
    }

}

sub GetDB {
    return DBI->connect('DBI:mysql:'.$config->{'database'}->{'name'}.';host='.$config->{'database'}->{'host'},
                                    $config->{'database'}->{'user'},
                                    $config->{'database'}->{'pass'});
}

sub GetNodes {
	my $s = "SELECT * FROM node";
	if (@ARGV) {
		$s = " SELECT * FROM node WHERE asset_tag REGEXP '".join("|",@ARGV) ."' or hostname REGEXP '".join("|",@ARGV) ."'"
	}
	return $db->selectall_hashref($s,'id');
}

sub printrunlist {
	my $RunList = &RunList($Node);
	my $tbrl = Text::Table->new(
        "Priority", "Description", "Url", "Template"
	    );
	for $priority ( sort { $a <=> $b } keys %{$RunList}) {
		my $ri = $RunList->{$priority};
		$tbrl->load(
			[$priority, $ri->{'description'}, $ri->{'url'}, $ri->{'template'}]
				);
	}
	print $tbrl."\n";
}

sub NodeStatus {
	my $Node = shift || return;
	my $sth = $db->prepare("SELECT * FROM node_status WHERE status_id='$Node->{'status_id'}'");
	$sth->execute;
	return $sth->fetchrow_hashref();
}

sub RunList {
	my $Node = shift || return;
	return $db->selectall_hashref("SELECT map_caste_rule.priority,map_caste_rule.caste_rule_id,caste_rule.description,caste_rule.template,caste_rule.url FROM caste_rule,map_caste_rule WHERE map_caste_rule.caste_rule_id=caste_rule.id AND caste_id='$Node->{'caste_id'}' order by priority",'priority');
}
