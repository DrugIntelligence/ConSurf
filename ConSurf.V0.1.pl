#!/usr/bin/perl -w
#####################################################################################################
#
#   This Script implement the ConSurf system for Identification of Functional Regions in Proteins 
#
#  ConSurf: the projection of evolutionary conservation scores of residues on protein structures                              
#        Landau M., Mayrose I., Rosenberg Y., Glaser F., Martz E., Pupko T., and Ben-Tal N.
#				 Nucl. Acids Res. 33:W299-W302. (2005)
#          			  Bioinformatics 19: 163-164. (2003)
#				      http://consurf.tau.ac.il/
# 
#                              
#   It is mainly Based on the Rate4Site Algorithm for detecting conserved amino-acid sites by computing 
#        the relative evolutionary rate for each site in the multiple sequence alignment (MSA).
#
#	  Comparison of site-specific rate-inference methods: Bayesian methods are superior.
#			Mayrose, I., Graur, D., Ben-Tal, N., and Pupko, T. 
#     			        Mol Biol Evol. 21:1781-1791. (2004).  
#                        http://www.tau.ac.il/~itaymay/cp/rate4site.html
#
#	For any questions or suggestions please contact us: bioSequence@tauex.tau.ac.il
#
#   
#####################################################################################################

use strict;
use Storable;

use Bio::SeqIO;
use Bio::AlignIO;
use Bio::Align::AlignI;
use Getopt::Long;

use lib "/groups/bioseq.home/HAIM/ConSurf_Exec";
use CONSURF_CONSTANTS;
use CONSURF_FUNCTIONS;
use prepareMSA;
use MSA_parser;
use TREE_parser;
use pdbParser;

my %FORM=();
my %VARS=();

# FOR LOCAL USE
use cp_rasmol_gradesPE_and_pipe;
$VARS{rasmolFILE} = "rasmol.scr";
$VARS{rasmol_isdFILE} = "isd_rasmol.scr";


## END FOR LOCAL USE



GetOptions(
          # Mandatory Argumants  
	    "PDB=s"=>\$VARS{pdb_file_name}, 		# PDB File
	    "CHAIN=s"=>\$FORM{chain},			# Chain ID
	    "Out_Dir=s"=>\$VARS{working_dir},		# Output Path
	   
	   # Given MSA mode parameters   
	    "MSA:s"=>\$VARS{user_msa_file_name},	# <MSA File Name>	(MANDATORY IF -m NOT USED)
	    "SEQ_NAME:s"=>\$FORM{msa_SEQNAME}, 		# <"Query sequence name in MSA file">  (MANDATORY IF -m NOT USED)
	    "Tree:s"=>\$VARS{user_tree_file_name},	# <Phylogenetic Tree (in Newick format)> (optional)	     
	    "MSA_Depth:s"=>\$VARS{unique_seqs},		# MSA Depth # REQUIERD FOR LOCAL VERSION ONLY
	    	    
	   # Building MSA mode 
	    "m"=>\$FORM{buildMSA},			# Builed MSA mode
	    "MSAprogram:s"=>\$FORM{MSAprogram},		# ["CLUSTALW"] or ["MUSCLE"] (default: MUSCLE)
	    "DB:s"=>\$FORM{database}, 			# ["SWISS-PROT"] or ["UNIPROT"] or ["UNIREF90"] [CLEAN_UNIPROT] (default: UniProt)  
	    "MaxHomol:s"=>\$FORM{MAX_NUM_HOMOL},	# <Max Number of Homologs to use for ConSurf Calculation, or "ALL"> (deafult: 50)
	    "Iterat:s"=>\$FORM{iterations},		# <Number of PsiBlast iterataion> (default: 1)
	    "ESCORE:s"=>\$FORM{ESCORE},    		# <Minimal E-value cutoff for Blast search> (default: 0.001)
	    "MinID:s"=>\$FORM{MinID},    		# <Minimal %ID to define sequence as homologus> (default: 0)
	    
	   # Rate4Site Parameters 
	    "Algorithm:s"=>\$FORM{algorithm}, 		# [LikelihoodML] or [Bayesian] (default: Bayesian)
	    "Matrix:s"=>\$FORM{matrix},			# [JTT] or [mtREV] or [cpREV] or [WAG] or [Dayhoff] (default JTT)
	    
	    "MinAlignScore:s"=>\$FORM{MinAlignmentScore}, # Minimal Alignment Score Between the Seq and The PDB Seq - ONLY LOCAL
	    "h"=>\$FORM{help}				# shows Help
	   );
$VARS{run_number}="";	   
#$VARS{user_msa_file_name}
# VERIFY USER INPUTS
if (!defined $FORM{alignment_score})
{
	$FORM{alignment_score}=60;
}

if (defined $FORM{help})
{
	&Print_Help();
	exit;
}
if (!defined $VARS{pdb_file_name} or !defined $FORM{chain} or ! defined $VARS{working_dir})
{
	die "===[FATAL ERROR] Missing Arguments; -PDB,-CHAIN,-Out_Dir must be specified\n"
}
if (!$FORM{buildMSA}) 
{
	if (!defined $VARS{user_msa_file_name} or !$FORM{msa_SEQNAME})
	{
		die "===[FATAL ERROR] Missing Arguments; -MSA,-SEQ_NAME must be given in MSA mode\n"
	}
	$VARS{protein_MSA}=$VARS{user_msa_file_name};	
}

if ((defined $VARS{user_tree_file_name}) and defined ($FORM{buildMSA}))
{
	print "===[WARNNING] The given tree would be ignored in Building MSA mode\n";
	$VARS{user_tree_file_name}="";
}
if ($VARS{pdb_file_name}=~/([A-Za-z0-9]{4})(.[A-Za-z0-9]+)?$/)
{
	$FORM{pdb_ID}=$1;
}		    

if (defined ($FORM{database}) and ($FORM{database} ne "UNIREF90") and ($FORM{database} ne "UNIPROT") and ($FORM{database} ne "SWISS-PROT") and $FORM{database} ne "CLEAN_UNIPROT")
{
	print "-DB can be only UNIREF90/UNIPROT/SWISS-PROT/CLEAN_UNIPROT\n";
	exit;
}



# Defaults , NOTE SOME OF THEM ARE IGNORED DURING THE PROGRAM BY IF ELSE MECHANISM
$FORM{iterations} = 1 if !defined($FORM{iterations});
$FORM{ESCORE} = 0.001 if !defined($FORM{ESCORE});
$FORM{MAX_NUM_HOMOL} = 50 if !defined($FORM{MAX_NUM_HOMOL});
$FORM{database}="UNIPROT" if !defined ($FORM{database});
$FORM{algorithm}="Bayesian" if !defined ($FORM{algorithm});
$FORM{MSAprogram}="MUSCLE" if !defined ($FORM{MSAprogram});
$FORM{matrix}="JTT" if !defined ($FORM{matrix});
$VARS{user_tree_file_name}="" if !defined ($VARS{user_tree_file_name});
$FORM{MinID}=0 if !defined ($FORM{MinID});
$VARS{pipeFile} ="$VARS{working_dir}/consurf_pipe.pdb";
my $submission_time;
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$submission_time = $hour . ':' . $min . ':' . $sec;
my $curr_time = $submission_time." $mday-".($mon+1)."-".($year+1900);

$VARS{submission_time}=$submission_time;
$VARS{run_log} = "$VARS{working_dir}/$FORM{pdb_ID}_$FORM{chain}.$FORM{database}_ConSurf.log";


$VARS{protein_seq} = "$FORM{pdb_ID}_$FORM{chain}_protein_seq.fas"; # a fasta file with the protein sequence - from PDB or from protein seq input

# general vars
$VARS{msa_format} = ""; # will be either: pir, fasta, nexus, clustalw, gcg, gde.


&open_log_file();




## This Script Run ConSurf Calculation Given MSA and PDB ID
    
my @gradesPE_Output = ();  # an array to hold all the information that should be printed to gradesPE
# in each array's cell there is a hash for each line from r4s.res.
# POS: position of that aa in the sequence ; SEQ : aa in one letter ;
# GRADE : the given grade from r4s output ; COLOR : grade according to consurf's scale
my %residue_freq = (); # for each position in the MSA, detail the residues 
my %position_totalAA = (); # for each position in the MSA, details the total number of residues

# these arrays will hold for each grade, the residues which corresponds to it.
# there are 2 arrays: in the @isd_residue_color, a grade with insufficient data, *, will classify to grade 10
# in the @no_isd_residue_color, the grade will be given regardless of the * mark
# PLEASE NOTE : the [0] position in those arrays is empty, because each position corresponds a color on a 1-10 scale
my @no_isd_residue_color = ();
my @isd_residue_color = ();
# these variables will be used in the pipe block, for view with FGiJ.
# $seq3d_grades_isd : a string. each position in the string corresponds to that ATOM (from the PDB) ConSurf grade. For Atoms with insufficient data - the grade will be 0
# $seq3d_grades - same, only regardeless of insufficient data
my ($seq3d_grades_isd, $seq3d_grades);

#These variables will hold the length of pdb ATOMS and the lenght of SEQRES/MSA_REFERENCE seq
# The data is filled by cp_rasmol_gradesPE_and_pipe::match_seqres_pdb
my ($length_of_seqres,$length_of_atom);

# programs
my $rate4s = CONSURF_CONSTANTS::RATE4SITE;
my $rate4s_slow = CONSURF_CONSTANTS::RATE4SITE_SLOW;

# outputs
$VARS{r4s_log} = "$FORM{pdb_ID}_$FORM{chain}_$FORM{database}_r4s.log";
$VARS{r4s_out} = "$FORM{pdb_ID}_$FORM{chain}_$FORM{database}_r4s.res";
$VARS{r4s_slow_log} = "$FORM{pdb_ID}_$FORM{chain}_$FORM{database}_r4s_slow.log";
$VARS{atom_positionFILE} = "$FORM{pdb_ID}_$FORM{chain}_$FORM{database}_atom_pos.txt";
$VARS{gradesPE} = "$FORM{pdb_ID}_$FORM{chain}_$FORM{database}_consurf.grades";
$VARS{r4s_tree}="$FORM{pdb_ID}_$FORM{chain}_$FORM{database}_Tree.txt";

# FOR LOCAL VERSION ONLY
#chimera files
$VARS{chimerax_script_for_figure} = $VARS{Used_PDB_Name}.'_consurf_'.$VARS{run_number}.'_Figure.chimerax';
$VARS{chimerax_script_for_figure_isd} = $VARS{Used_PDB_Name}.'consurf_'.$VARS{run_number}.'_Figure_isd.chimerax';

$VARS{chimera_color_script} = "/chimera/chimera_consurf.cmd";
$VARS{chimera_instructions} = "chimera_instructions.html";

$VARS{scf_for_chimera} = $VARS{Used_PDB_Name} .  "_consurf_" . $VARS{run_number}. ".scf";
$VARS{header_for_chimera} = $VARS{Used_PDB_Name} .  "_consurf_" . $VARS{run_number}. ".hdr";
$VARS{chimerax_file} = $VARS{Used_PDB_Name} .  "_consurf_" . $VARS{run_number}. ".chimerax";

$VARS{isd_scf_for_chimera} = $VARS{Used_PDB_Name} .  "_consurf_" . $VARS{run_number}. "_isd.scf";
$VARS{isd_header_for_chimera} = $VARS{Used_PDB_Name} .  "_consurf_" . $VARS{run_number}."_isd.hdr";
$VARS{isd_chimerax_file} =   $VARS{Used_PDB_Name}.  "_consurf_" . $VARS{run_number}. "_isd.chimerax";

$VARS{insufficient_data_pdb} = "";

# Atoms Section with consurf grades instead TempFactor Field
$VARS{ATOMS_with_ConSurf_Scores} = $VARS{working_dir}."/".$FORM{pdb_ID} . "_ATOMS_section_With_ConSurf.pdb";
$VARS{ATOMS_with_ConSurf_Scores_isd} =  $VARS{working_dir}."/".$FORM{pdb_ID}. "_ATOMS_section_With_ConSurf_isd.pdb";


$VARS{insufficient_data_pdb} = "";

$VARS{insufficient_data}="no";

if ($FORM{buildMSA})
{
	$VARS{running_mode}="_mode_pdb_no_msa";
}
if ((!$FORM{buildMSA}) and ($VARS{user_tree_file_name} eq ""))
{
	$VARS{running_mode}="_mode_pdb_msa";	
}
elsif ((!$FORM{buildMSA}) and ($VARS{user_tree_file_name} ne ""))
{
	$VARS{running_mode}="_mode_pdb_msa_tree";
}

#---------------------------------------------
# mode : include pdb
#---------------------------------------------
# create a pdbParser, to get various info from the pdb file
if ($VARS{running_mode} eq "_mode_pdb_no_msa" or $VARS{running_mode} eq "_mode_pdb_msa" or $VARS{running_mode} eq "_mode_pdb_msa_tree"){
    $VARS{pdb_file} = new pdbParser;
    $VARS{pdb_file}->read($VARS{pdb_file_name});
    # FIRST check if there is no seqres
    ($VARS{SEQRES_seq}, $VARS{ATOM_seq}) = &get_seqres_atom_seq();
    &analyse_seqres_atom();
}
#---------------------------------------------
# mode : no msa - with PDB or without PDB
#---------------------------------------------
if ($VARS{running_mode} eq "_mode_pdb_no_msa" or $VARS{running_mode} eq "_mode_no_pdb_no_msa"){
    # if there is pdb : we compare the atom and seqres
    if ($VARS{running_mode} eq "_mode_pdb_no_msa" and (defined($VARS{SEQRES_seq}) and length($VARS{SEQRES_seq}) > 0)){
        # align seqres and pdb sequences
        &compare_atom_seqres_or_msa("SEQRES");}
    $VARS{BLAST_out_file} = "$FORM{pdb_ID}_$FORM{chain}.$FORM{database}.protein_query.blast"; # file to hold blast output
    $VARS{BLAST_last_round} = "$FORM{pdb_ID}_$FORM{chain}.$FORM{database}.last_round.blast"; # file to hold blast output, last round
    $VARS{max_homologues_to_display}  = CONSURF_CONSTANTS::BLAST_MAX_HOMOLOGUES_TO_DISPLAY;
    if ($FORM{database} eq "SWISS-PROT"){
        $VARS{protein_db} = CONSURF_CONSTANTS::SWISSPROT_DB;}
    elsif ($FORM{database} eq "UNIREF90"){
    	$VARS{protein_db} = CONSURF_CONSTANTS::UNIREF90_DB;}
    elsif ($FORM{database} eq "CLEAN_UNIPROT"){
   	$VARS{protein_db} = CONSURF_CONSTANTS::CLEAN_UNIPROT_DB;}		
    else{
        $VARS{protein_db} = CONSURF_CONSTANTS::UNIPROT_DB;}
    # create the seqres fasta file, run blast
    &run_blast();
    &extract_round_from_blast();
    # choosing homologs, create fasta file for all legal homologs
    my %blast_hash = ();
    my %cd_hit_hash = ();
    $VARS{hit_redundancy} = CONSURF_CONSTANTS::FRAGMENT_REDUNDANCY_RATE;
    $VARS{hit_overlap} = CONSURF_CONSTANTS::FRAGMENT_OVERLAP;
    $VARS{hit_min_length} = CONSURF_CONSTANTS::FRAGMENT_MINIMUM_LENGTH;
    $VARS{min_num_of_hits} = CONSURF_CONSTANTS::MINIMUM_FRAGMENTS_FOR_MSA;
    $VARS{low_num_of_hits} = CONSURF_CONSTANTS::LOW_NUM_FRAGMENTS_FOR_MSA;
    $VARS{HITS_fasta_file} = "$FORM{pdb_ID}_$FORM{chain}.$FORM{database}.homolougs.fas";
    $VARS{HITS_rejected_file} = "$FORM{pdb_ID}_$FORM{chain}.$FORM{database}.rejected_homolougs.fas";
    if ($FORM{MinID}==0)
    {
    	&choose_homologoues_from_blast(\%blast_hash);
    }
    else
    {
    	&choose_homologoues_from_blast_with_lower_identity_cutoff(\%blast_hash);
    }
    
    # screen homolougs by redundancy rate, according to clusters (CD-HIT)
    $VARS{cd_hit_out_file} = "$FORM{pdb_ID}_$FORM{chain}.$FORM{database}.cdhit.out";
    my $num_of_unique_seq=cluster_homologoues(\%cd_hit_hash, \%blast_hash);
    $VARS{unique_seqs}=$num_of_unique_seq;	
    $VARS{FINAL_sequences} = "$FORM{pdb_ID}_$FORM{chain}.$FORM{database}.final_homolougs.fas";
    &choose_final_homologoues(\%cd_hit_hash, \%blast_hash);
    $VARS{protein_MSA} = "$FORM{pdb_ID}_$FORM{chain}_query_msa.$FORM{database}.aln";
    &create_MSA;
    if ($VARS{running_mode} eq "_mode_pdb_no_msa")
    {
    	$VARS{msa_SEQNAME}="$FORM{pdb_ID}_SEQRES_$FORM{chain}"; #CONSIDER TO CHANGE    
    }
}

#---------------------------------------------
# mode :  include msa
#---------------------------------------------

elsif ($VARS{running_mode} eq "_mode_pdb_msa" or $VARS{running_mode} eq "_mode_msa" or $VARS{running_mode} eq "_mode_pdb_msa_tree" or $VARS{running_mode} eq "_mode_msa_tree"){
    # check that there are at least 5 sequecnes in the MSA
    # extract the query sequence from the MSA
    # change the MSA sequences names to numbers
    # change the MSA format to clustalw
    # align the seqres/atom sequence with that of the query
    &determine_msa_format();
    my %MSA_sequences = (); # a hash to hold all the MSA sequences, : key - sequence id, value - sequence
    $VARS{user_msa_fasta} = "$FORM{pdb_ID}_$FORM{chain}_msa_file.fas"; # if the file is not in fasta format, we create a fasa copy of it
    &get_info_from_msa(\%MSA_sequences);
    $VARS{query_string} = $FORM{msa_SEQNAME};
    $VARS{MSA_query_seq} = $MSA_sequences{$VARS{query_string}};
    $VARS{MSA_query_seq} =~ s/\-//g; # remove gpas from the query sequence
    #---------------------------------------------
    # mode :  include tree
    #---------------------------------------------
    if ($VARS{running_mode} eq "_mode_pdb_msa_tree" or $VARS{running_mode} eq "_mode_msa_tree"){
        &check_validity_tree_file();
        my %tree_nodes = (); # a hash to hold all the nodes in the tree (as keys)
        &extract_nodes_from_tree(\%tree_nodes);
        #foreach my $node (sort (keys %tree_nodes)){
        #    print OUTPUT "NODE: $node <br />";
        #}
        &check_msa_tree_match(\%MSA_sequences, \%tree_nodes);
    }
    &compare_atom_seqres_or_msa("MSA") if ($VARS{running_mode} eq "_mode_pdb_msa" or $VARS{running_mode} eq "_mode_pdb_msa_tree");
    $VARS{protein_MSA} = $VARS{user_msa_fasta};
    $VARS{msa_SEQNAME}=$FORM{msa_SEQNAME};
}
&run_rate4site;
&assign_colors_according_to_r4s_layers(\@gradesPE_Output);
&read_residue_variety(\%residue_freq, \%position_totalAA); # put value in $VARS{num_of_seqs_in_MSA}

#---------------------------------------------
# mode : include pdb
#---------------------------------------------
# in order to create 3D outputs, we need to compare the ATOM to the sequence from rate4site 
if ($VARS{running_mode} eq "_mode_pdb_no_msa" or $VARS{running_mode} eq "_mode_pdb_msa" or $VARS{running_mode} eq "_mode_pdb_msa_tree"){
    &create_atom_position_file; # this file will be used later to create the output which aligns rate4site sequence with the ATOM records
    my %r4s2pdb = (); # key: poistion in SEQRES/MSA, value: residue name with position in atom (i.e: ALA22:A)
    &match_pdb_to_seq(\%r4s2pdb); 
    &create_gradesPE(\%r4s2pdb);          
    &create_rasmol; #This will create the 2 rasmol scripts (one with isd and one without)
    &create_pipe_file; # This will create the pipe file for FGiJ
    &replace_TmpFactor_Consurf; #Will replace the TempFactor Column with the ConSurf Grades (will create also isd file if relevant)
   # &create_chimera; #This Will create the script for chimera coloring
}


### SUBRUTINES #####
####################

sub create_working_dir{
    if (!-d $VARS{working_dir}){
        mkdir $VARS{working_dir} or &exit_on_error('sys_error', "create_working_dir : the directory $VARS{working_dir} was not created $!");
    }
    chmod 0755, $VARS{working_dir};
}
#---------------------------------------------
sub analyse_seqres_atom{
    # there is no ATOM field in the PDB
    if ($VARS{ATOM_seq} eq ""){
        &exit_on_error('user_error',"There is no ATOM derived information in the PDB file. Please refer to the OVERVIEW for detailed information about the PDB format.");
    }
    # there is no SEQRES field in the PDB
    if ($VARS{SEQRES_seq} eq ""){
        my $msg = "Warning: There is no SEQRES derived information in the PDB file. The calculation will be based on the ATOM derived sequence. ";
        if ($VARS{running_mode} eq "_mode_pdb_no_msa"){
            $msg.= "If this sequence is incomplete, we recommend to re-run the server using an external multiple sequence alignment file, which is based on the complete protein sequence.";
        }
        print LOG "analyse_seqres_atom : There is no SEQRES derived information in the PDB file.\n";
        print_message_to_output($msg);
    }
    # if modified residues exists, print them to the screen
    if (defined($VARS{pdb_file}->get("MODIFIED_COUNT$FORM{chain}.raw")) and $VARS{pdb_file}->get("MODIFIED_COUNT$FORM{chain}.raw")> 0 ){
        if (defined($VARS{SEQRES_seq}) and length($VARS{SEQRES_seq}) > 0 and ($VARS{pdb_file}->get("MODIFIED_COUNT$FORM{chain}.raw") / length($VARS{SEQRES_seq}) > CONSURF_CONSTANTS::MAXIMUM_MODIFIED_PERCENT) ){
            &exit_on_error('user_error', "Too many modified residues were found in SEQRES field.");
        }
        print LOG "analyse_seqres_atom : modified residues found\n";
        
    }
}
#---------------------------------------------
sub compare_atom_seqres_or_msa{

    my $what_to_compare = shift;
    # in case there are both seqres and atom fields, checks the similarity between the 2 sequences.
    my $atom_length = length($VARS{ATOM_seq});
    my ($other_query_length, $other_query_seq, %query_line);
    my $two_fastas = "PDB_$what_to_compare"."_$FORM{pdb_ID}_$FORM{chain}.fasta2"; #CHANGHING THE NAMES
    my $clustalw_out = "PDB_$what_to_compare"."_$FORM{pdb_ID}_$FORM{chain}.out";
    $VARS{pairwise_aln} = "PDB_$what_to_compare"."_$FORM{pdb_ID}_$FORM{chain}.aln";

    if ($what_to_compare eq "SEQRES"){
        if ($VARS{SEQRES_seq} eq ""){
            $other_query_length = 0;}
        else{
            $other_query_length = length($VARS{SEQRES_seq});}
        $other_query_seq = $VARS{SEQRES_seq};
    }
    else{
        $other_query_length = length ($VARS{MSA_query_seq});
        $other_query_seq = $VARS{MSA_query_seq};
    }

    my $alignment_score;
    my $atom_line = "sequence extracted from the ATOM field of the PDB file";
    $query_line{SEQRES} = "sequence extracted from the SEQRES field of the PDB file";
    $query_line{MSA} = "sequence extracted from the MSA file";

    # compare the length of ATOM and SEQRES. output a message accordingly
    if ($other_query_length!=0 and $other_query_length < $atom_length){
        print_message_to_output("The ".$query_line{$what_to_compare}." is shorter than the $atom_line. The $what_to_compare sequence has $other_query_length residues and the ATOM sequence has $atom_length residues. The calculation continues nevertheless.");
    }
    if ($atom_length < $other_query_length){
        if ($atom_length < ($other_query_length * 0.2)){
            exit_on_error('user_error', "The $atom_line is significantly shorter than the ".$query_line{$what_to_compare}.". The $what_to_compare sequence has $other_query_length residues and the ATOM sequence has only $atom_length residues.");
        }
        else{
            print_message_to_output("The $atom_line is shorter than the ".$query_line{$what_to_compare}.". The $what_to_compare sequence has $other_query_length residues and the ATOM sequence has $atom_length residues. The calculation continues nevertheless.");
        }
    }

    # run clustalw to see the match between ATOM and SEQRES sequences
    print LOG "compare_atom_seqres_or_msa : run clustalw to see the match between ATOM and $what_to_compare sequences\n";
    #if (!-e "$VARS{working_dir}/$two_fastas")
    #{
    open FAS, ">$VARS{working_dir}/$two_fastas" or exit_on_error('sys_error', "compare_atom_seqres_or_msa : Cannot open the file $two_fastas for writing $!");
    print FAS ">".$what_to_compare."_$FORM{chain}\n$other_query_seq\n>ATOM_$FORM{chain}\n$VARS{ATOM_seq}\n";
    close FAS;
    #}
    my $command = "cd ".$VARS{working_dir}."; ".CONSURF_CONSTANTS::CLUSTALW." -INFILE=".$VARS{working_dir}."/".$two_fastas." -gapopen=1 -OUTFILE=$VARS{working_dir}/$VARS{pairwise_aln}> ".$VARS{working_dir}."/".$clustalw_out;
#    my $command = "cd ".$VARS{working_dir}."; ".CONSURF_CONSTANTS::CLUSTALW." ".$two_fastas." -gapopen=1  > ".$VARS{working_dir}."/".$clustalw_out;
    print LOG "compare_atom_seqres_or_msa : run $command\n";
    `$command`;
    if (!-e "$VARS{working_dir}/$VARS{pairwise_aln}" or -z "$VARS{working_dir}/$VARS{pairwise_aln}" or !-e "$VARS{working_dir}/$clustalw_out" or -z "$VARS{working_dir}/$clustalw_out"){
        exit_on_error('sys_error',"compare_atom_seqres_or_msa : one of clustalw outputs were not create; $clustalw_out and/or $VARS{pairwise_aln}");
    }
    open OUT, "$VARS{working_dir}/$clustalw_out" or exit_on_error('sys_error', "compare_atom_seqres_or_msa : Cannot open the file $clustalw_out for reading $!");
    while(<OUT>){
        if(/Sequences.+Aligned.+Score:\s+(\d+)/){
            $alignment_score = $1;
            last;
        }
    }
    close OUT;

    if ($alignment_score < 100){
        if ($alignment_score < $FORM{MinAlignmentScore}){
            exit_on_error('user_error',"The Score of the alignment between the ".$query_line{$what_to_compare}." and the $atom_line is ONLY $alignment_score% identity. See $VARS{pairwise_aln} pairwise alignment.");
        }
        else{
            print_message_to_output("The Score of the alignment between the ".$query_line{$what_to_compare}." and the $atom_line is  $alignment_score% identity. See $VARS{pairwise_aln} pairwise alignment. The calculation continues nevertheless.");
        }
    }

    # remove the dnd file
    my $cmd = "rm *.dnd";
    chdir $VARS{working_dir};
    `$cmd`;
}
#------------------------------------------
# In PDB mode: create a fasta file with the protein SEQRES sequence (if no seqres - than with the ATOM sequence)
# run blast according to user's input
sub run_blast{
    unless ($VARS{running_mode} eq "_mode_no_pdb_no_msa"){
        open FAS, ">$VARS{working_dir}/$VARS{protein_seq}" or exit_on_error('sys_error',"run_blast : cannot open the file $VARS{working_dir}/$VARS{protein_seq} for writing $!");
        if ($VARS{SEQRES_seq} eq ""){
            print FAS ">PDB_ATOM\n$VARS{ATOM_seq}\n";
        }
        else{
            print FAS ">PDB_SEQRES\n$VARS{SEQRES_seq}\n";
        }
        close FAS;

        if (!-e "$VARS{working_dir}/$VARS{protein_seq}" or -z "$VARS{working_dir}/$VARS{protein_seq}"){
            exit_on_error('sys_error',"run_blast : the file $VARS{working_dir}/$VARS{protein_seq} was not created");
        }
    }

    my $cmd = "cd $VARS{working_dir}; ".CONSURF_CONSTANTS::BLASTPGP." -i $VARS{working_dir}/$VARS{protein_seq} -e $FORM{ESCORE} -d $VARS{protein_db} -o $VARS{working_dir}/$VARS{BLAST_out_file} -j $FORM{iterations} -v $VARS{max_homologues_to_display} -b $VARS{max_homologues_to_display} -F F";
    print LOG "run_blast : running: $cmd\n";
    my $ans = `$cmd`;
    print LOG "run_blast : ans from blast run: $ans\n" if $ans ne "";
    if (!-e "$VARS{working_dir}/$VARS{BLAST_out_file}" or (-e "$VARS{working_dir}/$VARS{BLAST_out_file}" and -z "$VARS{working_dir}/$VARS{BLAST_out_file}")){
        exit_on_error('sys_error',"run_blast : run of blast fail. $VARS{working_dir}/$VARS{BLAST_out_file} is zero or not exists");
    }
}

#---------------------------------------------
# read the blast result and extract last roun number (if exists)
# create a "shorter" blast file - to include only the information from blast's last round
sub extract_round_from_blast{
    my $last_round_number = 0;
    my $found_converged = 0;
    my $ret = "";

    my @ans = prepareMSA::get_blast_round("$VARS{working_dir}/$VARS{BLAST_out_file}");
    if ($ans[0] eq "err"){
        exit_on_error('sys_error',"extract_round_from_blast : $ans[1]");
    }
    elsif($ans[0] eq "no_hits"){
        my $err = "No Blast hits were found.  You may try to";
        if ($FORM{database} eq "SWISS-PROT"){
            $err.=":\n1. run your query using UniProt database.\n2. ";
        }
        $err.= " increase the Evalue.\n";
        exit_on_error('user_error',$err);
    }
    else{
        $last_round_number = $ans[0];
        $found_converged = $ans[1];
    }
    # if there is more than 1 round, extract blast hits only from the last round
    if ($last_round_number>1){
        @ans = prepareMSA::print_blast_according_to_round("$VARS{working_dir}/$VARS{BLAST_out_file}", $last_round_number, "$VARS{working_dir}/$VARS{BLAST_last_round}");
        if ($ans[0] eq "err"){
            exit_on_error('sys_error',"extract_round_from_blast : $ans[1]");
        }
        if (-e "$VARS{working_dir}/$VARS{BLAST_last_round}" and !-z "$VARS{working_dir}/$VARS{BLAST_last_round}"){
            my $cmd = "mv $VARS{BLAST_last_round} $VARS{BLAST_out_file}";
            chdir $VARS{working_dir};
            `$cmd`;
        }
        else{
            print LOG "extract_round_from_blast : the file $VARS{working_dir}/$VARS{BLAST_last_round} was not created. The hits will be collected from the original blast file";
        }
    }
}
#---------------------------------------------
sub choose_homologoues_from_blast{
    my $ref_blast_hash = shift;
    print LOG "choose_homologoues_from_blast : running prepareMSA::choose_homologoues_from_blast\n";
    my @ans = prepareMSA::choose_homologoues_from_blast("$VARS{working_dir}/", "$VARS{working_dir}/$VARS{protein_seq}", $VARS{hit_redundancy}, $VARS{hit_overlap}, $VARS{hit_min_length}, $VARS{min_num_of_hits}, "$VARS{working_dir}/$VARS{BLAST_out_file}", $VARS{HITS_fasta_file}, $VARS{HITS_rejected_file}, $ref_blast_hash);
    if ($ans[0] eq "sys"){
        exit_on_error('sys_error',$ans[1]);
    }
    elsif ($ans[0] eq "user"){
        exit_on_error('user_error',"According to the parameters of this run, $ans[1] You can try to:<ol><li>Re-run the server with a multiple sequence alignment file of your own.</li><li>Decrease the Evalue.</li></ol>");
    }
    if (!-e "$VARS{working_dir}/$VARS{HITS_fasta_file}" or -z "$VARS{working_dir}/$VARS{HITS_fasta_file}"){
        exit_on_error('sys_error',"choose_homologoues_from_blast : the file $VARS{working_dir}/$VARS{HITS_fasta_file} was not created or contains no data");
    }
}
#---------------------------------------------
sub choose_homologoues_from_blast_with_lower_identity_cutoff{
    my $ref_blast_hash = shift;
    print LOG "choose_homologoues_from_blast : running prepareMSA::choose_homologoues_from_blast_with_lower_identity_cutoff\n";
    my @ans = prepareMSA::choose_homologoues_from_blast_with_lower_identity_cutoff("$VARS{working_dir}/", "$VARS{working_dir}/$VARS{protein_seq}", $VARS{hit_redundancy}, $VARS{hit_overlap}, $VARS{hit_min_length}, $FORM{MinID}, $VARS{min_num_of_hits}, "$VARS{working_dir}/$VARS{BLAST_out_file}", $VARS{HITS_fasta_file}, $VARS{HITS_rejected_file}, $ref_blast_hash);
    if ($ans[0] eq "sys"){
        exit_on_error('sys_error',$ans[1]);
    }
    elsif ($ans[0] eq "user"){
        exit_on_error('user_error',"According to the parameters of this run, $ans[1] You can try to:\n1.Re-run the server with a multiple sequence alignment file of your own.\n2.Decrease the Evalue.\n3. Increase The Minimal %ID");
    }
    if (!-e "$VARS{working_dir}/$VARS{HITS_fasta_file}" or -z "$VARS{working_dir}/$VARS{HITS_fasta_file}"){
        exit_on_error('sys_error',"choose_homologoues_from_blast : the file $VARS{working_dir}/$VARS{HITS_fasta_file} was not created or contains no data");
    }
}
#---------------------------------------------
sub cluster_homologoues{
    my $ref_cd_hit_hash = shift;
    my $ref_blast_hash = shift;
    my $msg = "";
    print LOG "cluster_homologoues : running prepareMSA::create_cd_hit_output\n";
    my @ans = prepareMSA::create_cd_hit_output("$VARS{working_dir}/", $VARS{HITS_fasta_file}, $VARS{cd_hit_out_file}, $VARS{hit_redundancy}/100, CONSURF_CONSTANTS::CD_HIT_DIR, $ref_cd_hit_hash, "from_ibis");
    if ($ans[0] eq "sys"){
        exit_on_error('sys_error',$ans[1]);
    }
    my $total_num_of_hits = keys (%$ref_cd_hit_hash);
    my $num_of_blast_hits = keys (%$ref_blast_hash);
    $FORM{MAX_NUM_HOMOL}=$total_num_of_hits if (($FORM{MAX_NUM_HOMOL} eq 'all') or ($FORM{MAX_NUM_HOMOL} eq "ALL"));
    # less seqs than the minimum: exit
    if ($total_num_of_hits < $VARS{min_num_of_hits}){
        if ($total_num_of_hits<=1){
            $msg = "There is only 1 ";
        }
        else{
            $msg = "There are only $total_num_of_hits ";
        }
        $msg.="$VARS{cd_hit_out_file} unique PSI-BLAST hits</a>. The minimal number of sequences required for the calculation is $VARS{min_num_of_hits}. You may try to:\n 1. Re-run the server with a multiple sequence alignment file of your own.\n 2.Decrease the Evalue.\n";
        exit_on_error('user_error',$msg);
    }
    # less seqs than 10 : output a warning.
    elsif($total_num_of_hits+1 < $VARS{low_num_of_hits}){
        $msg = "<font color='red'><b>Warning:</font></b> There are ";
        if( $total_num_of_hits+1 < $num_of_blast_hits){# because we will add the query sequence itself to all the unique sequences.
            $msg.="$num_of_blast_hits PSI-BLAST hits, only ".($total_num_of_hits+1)." of them are";
        }
        else{
            $msg.=$total_num_of_hits+1;
        }
        $msg.=" unique sequences. The calculation is performed on the ".($total_num_of_hits+1)." unique sequences, but it is recommended to run the server with a multiple sequence alignment file containing at least $VARS{low_num_of_hits} sequences.";
    }
    # different message for different values of $num_of_blast_hits, $total_num_of_hits, $FORM{MAX_NUM_HOMOL}
    else{
        $msg = "There are $num_of_blast_hits PSI-BLAST hits, ".($total_num_of_hits+1)." of them are unique sequences.\nThe calculation is performed on the ";
        if ($total_num_of_hits <= $FORM{MAX_NUM_HOMOL}){
            $msg.=($total_num_of_hits+1)." unique sequences.";
        }
        else{
            $msg.="$FORM{MAX_NUM_HOMOL} sequences with the lowest E-value.";
        }
    }
    &print_message_to_output($msg);
    if (-e "$VARS{working_dir}/$VARS{HITS_rejected_file}" and !-z "$VARS{working_dir}/$VARS{HITS_rejected_file}"){
        &print_message_to_output("If you wish to view the list of sequences which produced significant alignments in blast, but were not chosen as hits please have a look at: $VARS{HITS_rejected_file}");
    }
    return ($total_num_of_hits+1);
}
#---------------------------------------------
sub choose_final_homologoues{
    my $ref_cd_hit_hash = shift;
    my $ref_blast_hash = shift;
    unless (open FINAL, ">$VARS{working_dir}/$VARS{FINAL_sequences}"){exit_on_error('sys_error',"choose_final_homologoues : cannot open the file $VARS{FINAL_sequences} for writing $!");}
    if($VARS{running_mode} eq "_mode_no_pdb_no_msa"){
        $VARS{query_string} = "Input_protein_seq";
        print FINAL ">$VARS{query_string}\n$VARS{protein_query_seq}\n";
        $VARS{MSA_query_seq} = $VARS{protein_query_seq};
    }
    elsif ($VARS{SEQRES_seq} ne ""){
        $VARS{query_string} = "$FORM{pdb_ID}_SEQRES_$FORM{chain}";
        print FINAL ">$VARS{query_string}\n$VARS{SEQRES_seq}\n";
        $VARS{MSA_query_seq} = $VARS{SEQRES_seq};
    }
    else{
        $VARS{query_string} = "$FORM{pdb_ID}_ATOM_$FORM{chain}";
        print FINAL ">$VARS{query_string}\n$VARS{ATOM_seq}\n";
        $VARS{MSA_query_seq} = $VARS{ATOM_seq};
    }
    close FINAL;
    my $final_file_size = (-s "$VARS{working_dir}/$VARS{FINAL_sequences}"); # take the size of the file before we add more sequences to it
    my @ans = prepareMSA::sort_sequences_from_eval($ref_blast_hash ,$ref_cd_hit_hash, ($FORM{MAX_NUM_HOMOL}-1), "$VARS{working_dir}/$VARS{FINAL_sequences}");
    if ($ans[0] eq "err"){exit_on_error('sys_error',$ans[1]);}
    # check that more sequences were added to the file
    unless ($final_file_size < (-s "$VARS{working_dir}/$VARS{FINAL_sequences}")){
        exit_on_error('sys_error', "choose_final_homologoues : the file $VARS{working_dir}/$VARS{FINAL_sequences} doesn't contain sequences");
    }
}
#---------------------------------------------
#---------------------------------------------
sub determine_msa_format{
    # the routine trys to read the MSA format. If there are errors - reports it to the user.


    # alternative messages to the user
    my $clustal_msg = "As an alternative you can also re-run the ConSurf session using a different alignment format, preferably ClustAlW format.\n";
    my $conversion_progam = "It is recommend to use EBI's biosequence conversion tool.\n";
    my $msa_info_msg = "Read more on MSA formats\n";

    print LOG "determine_msa_format : calling MSA_parser::determine_msa_format($VARS{user_msa_file_name})\n";
    my @msa_format = &MSA_parser::determine_msa_format("$VARS{user_msa_file_name}");
    if ($msa_format[0] eq "err"){
        &exit_on_error('user_error',"The MSA file $VARS{protein_MSA} is not in one of the formats supported by ConSurf: NBRF/PIR, Pearson (Fasta), Nexus, Clustal, GCG/MSF.\nPlease check the following items and try to run ConSurf again:\n1. The file should be saved as plain text (e.g. file type 'txt' in windows or 'MS-Dos' from Word in Mac).\n2. The file should not contain unnecessary characters (You can check it with 'Notepad' editor).\n3. The same sequence name must not be repeated more then once.\n".$msa_info_msg);
    }
    else{
        print LOG "determine_msa_format : MSA format is : $msa_format[1]\n";
        $VARS{msa_format} = $msa_format[1];
        }

    # format is known. Now check if the sequences are readable and contain legal characters
    print LOG "determine_msa_format : calling MSA_parser::check_msa_licit($VARS{user_msa_file_name}, $VARS{msa_format})\n";
    # check each sequence in the MSA for illegal characters
    my @ans = MSA_parser::check_msa_licit("$VARS{user_msa_file_name}", $VARS{msa_format});

    # there was an error
    if ($ans[0] ne "OK"){
        print LOG "determine_msa_format : an error was found while check_msa_licit\n";
        my $msg = "The MSA file $VARS{protein_MSA} which appears to be in $VARS{msa_format} format, ";
        # if there were illegal characters - report them
        if($ans[1] =~ /^SEQ_NAME: (.+)?/){
            # report in which sequence were the characters found
            my $_seq_name = $1 if (defined $1);
            $ans[2] =~ /^IRR_CHAR: (.+)?/;
            my $_irr_chars = $1 if (defined $1);
            print LOG "determine_msa_format : found irregular chars: $_irr_chars in sequence: $_seq_name\n";
            $msg .= "contains non-standard characters";
            $msg .= ": ". qq($_irr_chars) if (defined $_irr_chars and $_irr_chars =~ /\S+/);
            $msg .= " in the sequence named '$_seq_name'" if (defined $_seq_name and $_seq_name =~ /\S+/);
            $msg .= ". To fix the format please replace all non-standard characters with standard characters (gaps : \"-\" Amino Acids : \"A\" , \"C\" , \"D\" .. \"Y\") and resubmit your query.\n";
        }
        # the MSA file was not opened correctly
        elsif ($ans[1] eq "could not read msa"){
            print LOG $ans[1]."\n";
            $msg.= "could not be read by the server. Please convert it, preferably to ClustAlW format, then resubmit your query.\n".$conversion_progam.$msa_info_msg;
        }
        # an exception found while trying to open the alignment
        elsif($ans[1] eq "exception"){
            print LOG $ans[1]."\n";
            $msg .= "could not be read. Please note that the sequences should contain only standard characters (gaps : \"-\" Amino Acids : \"A\" , \"C\" , \"D\" .. \"Y\"). Please replace all non-standard characters with standard characters and resubmit your query.\n";
            $msg.=$clustal_msg.$msa_info_msg if ($VARS{msa_format} ne "clustalw");
        }
        &exit_on_error('user_error',$msg);
    }
    else{
        print LOG "determine_msa_format : MSA is legal!\n";
    }
    #&find_query_in_msa();
}
#-------------------------------------------
sub get_info_from_msa{
    # extract all the sequence identifiers and the sequences themselves to the hash %MSA_sequences (here - transmitted by reference)
    # create a fasta format file for this msa, since it is more convenient to work with
    # NOTE!! on some formats (I saw it in "pir") the bioPerl modoule which reads the MSA shortens the sequences!
#---------------------------------------------
    my $msa_ref = shift;
    print LOG "get_info_from_msa : running : MSA_parser::get_info_from_msa($VARS{user_msa_file_name}, $VARS{msa_format}, $msa_ref, $VARS{working_dir}/$VARS{user_msa_fasta})\n";
    my @ans = MSA_parser::get_info_from_msa("$VARS{user_msa_file_name}",$VARS{msa_format},$msa_ref, "$VARS{working_dir}/$VARS{user_msa_fasta}");
    #my @ans = info("$VARS{working_dir}/$VARS{user_msa_file_name}",$VARS{msa_format},$msa_ref);
    print LOG "get_info_from_msa : answer is: $ans[0]\n";
    # an error was found:
    unless ($ans[0] eq "OK"){
        print LOG "get_info_from_msa : Error was found: $ans[1]\n";
        # general error message
        my $msg = "The MSA file $VARS{user_msa_file_name}, which appears to be in $VARS{msa_format} format, ";
        if ($ans[1] eq "exception"){
            $msg .= "could not be read by the server. Please note that the sequences should contain only standard characters (gaps : \"-\" Amino Acids : \"A\" , \"C\" , \"D\" .. \"Y\"). Please replace all non-standard characters with standard characters and resubmit your query.\n";
        }
        elsif ($ans[1] eq "could not read msa"){
            $msg.= "could not be read. Please convert it, preferably to ClustAlW format, then resubmit your query.\n"
        }
        # the MSA was read correctly , but there was a problem with the sequences ids
        elsif ($ans[1] eq "no seq id" or $ans[1] =~ /^duplicity/){
            $msg = "An error was found in the uploaded MSA file $VARS{user_msa_file_name}:\n";
            if ($ans[1] eq "no seq id"){
                $msg.="At lease one of the sequences did not have an identifier (a sequence id).\n";
            }
            elsif($ans[1] =~ /duplicity (.*)$/){
                my $seq_id = $1;
                $msg .= "The same sequence identifier: '$seq_id' appeared more than once. ";
            }
            $msg .= "Note that:Each sequence in the MSA should have a uniuqe sequence name.\nIf the sequence name contains characters such as '\\', '/', '[',']' - there may be problems reading the MSA correctly.\nPlease correct your file and re-run\n";
        }
        &exit_on_error('user_error',$msg);

    }
    if (!-e "$VARS{working_dir}/$VARS{user_msa_fasta}" or -z "$VARS{working_dir}/$VARS{user_msa_fasta}"){
        &exit_on_error('sys_error',"get_info_from_msa : the file $VARS{working_dir}/$VARS{user_msa_fasta} was not created or zero");
    }
    my $num_of_seq = (keys %$msa_ref);
    print LOG "MSA contains $num_of_seq sequences\n";
    # less than 5 sequences: exit
    if ($num_of_seq < 5){
        &exit_on_error('user_error',"The MSA file contains only $num_of_seq sequences. The minimal number of homologues required for the calculation is 5.");
    }
    #foreach my $key (keys %$msa_ref){
    #    print OUTPUT "~~$key~~<br />\n";
    #}
    # exit if the query name was not found in the MSA
    unless (exists $msa_ref->{$FORM{msa_SEQNAME}}){
        my $msg = "The query sequence name '$FORM{msa_SEQNAME}' is not found in the <a href = \"$VARS{user_msa_file_name}\">MSA file</a>. (It should be written exactly as it appears in the MSA file)";
        if ($FORM{msa_SEQNAME} =~ /^\s+/ or $FORM{msa_SEQNAME} =~ /\s+$/){
            $msg.= ".Looks like there are extra spaces. Please check.";
        }
        if ($FORM{msa_SEQNAME} =~ /[\[\]\/\\;]/){
            $msg.= ".Please note that signs such as: '[', ']', '/', may be problematic as sequence identifier.";
        }
        &exit_on_error('user_error',$msg);
    }
}
#---------------------------------------------
sub check_validity_tree_file{
    my %ERR = ();
    print LOG "check_validity_tree_file : calling TREE_parser::check_validity_tree_file($VARS{user_tree_file_name})\n";
    TREE_parser::check_validity_tree_file("$VARS{user_tree_file_name}", \%ERR);
    if (exists $ERR{left_right} or exists $ERR{noRegularFormatChar}){
        my $msg = "The TREE file $VARS{user_tree_file_name}, which appears to be in Newick format, ";
        if ($ERR{left_right}){
            $msg.="is missing parentheses.";}
        elsif (exists $ERR{noRegularFormatChar}){
            $msg.="contains the following non-standard characters: ". qq($ERR{noRegularFormatChar});}
        $msg.="\nPlease fix the file and re-run your query.\n";
        &exit_on_error('user_error',$msg);
    }
    print LOG "check_validity_tree_file : tree is valid\n";
}
#---------------------------------------------
sub extract_nodes_from_tree{
    my $ref_to_tree_nodes = shift;
    unless (open TREEFILE, "$VARS{user_tree_file_name}"){&exit_on_error('sys_error', "extract_nodes_from_tree : could not open $VARS{working_dir}/$VARS{user_tree_file_name} $!");}
    my $tree = "";
    while (<TREEFILE>){
        chomp;
        $tree .= $_ if (/\S+/);
    }
    close TREEFILE;
    print LOG "extract_nodes_from_tree : calling TREE_parser::extract_nodes_from_tree()\n";
    my @ans = TREE_parser::extract_nodes_from_tree($tree, $ref_to_tree_nodes);
    unless ($ans[0] eq "OK"){
        if ($ans[1] =~ /^duplicity: (.*)$/){
            &exit_on_error('user_error', "TREE fileT $VARS{user_tree_file_name}, which appears to be in Newick format, contains the same node identifier: '$1' more than once.\nNote that each node in the tree should have a uniuqe identifier. Please correct your file and re-upload your query to the server.\n");
        }
    }
}
#---------------------------------------------
sub check_msa_tree_match{
    my ($ref_msa_seqs, $ref_tree_nodes) = @_;
    my $err_msg = "Note that the search is case-sensitive!\nPlease correct your files and re-upload your query to the server.\n";

    print LOG "check_msa_tree_match : check if all the nodes in the tree are also in the MSA\n";

    # check that all the tree nodes are in the msa
    foreach my $node (sort (keys %$ref_tree_nodes)){
        unless (exists $ref_msa_seqs->{$node}){
            &exit_on_error('user_error', "The TREE file $VARS{user_tree_file_name} is inconsistant with the MSA file $VARS{user_msa_file_name}.\nThe node '$node' is found in the TREE file, but there is no sequence in the MSA file with that exact name. ".$err_msg);
        }
       
    }
    print LOG "check_msa_tree_match : check if all the sequences in the MSA are also in the tree\n";
    #check that all the msa nodes are in the tree
    foreach my $seq_name (sort (keys %$ref_msa_seqs)){
        unless (exists $ref_tree_nodes->{$seq_name}){
            &exit_on_error('user_error', "The MSA file $VARS{protein_MSA} is inconsistant with the TREE file $VARS{user_tree_file_name}.The Sequence name '$seq_name' is found in the MSA file, but there is no node with that exact name in the TREE file. $err_msg");
        }
       
    }
}
#---------------------------------------------
sub get_seqres_atom_seq{
    # extract the sequences from the pdbParser
    my $seqres = "";
    my $atom = "";
    if (defined (@{$VARS{pdb_file}->{SEQRES_chains}})){
        foreach my $chainid (@{$VARS{pdb_file}->{SEQRES_chains}}){
            if (($chainid eq " " and $FORM{chain} =~ /none/i) or $chainid =~ /$FORM{chain}/i){
                $seqres = $VARS{pdb_file}->get("SEQRES$chainid.raw");
                last;
            }
        }
    }
    if (defined (@{$VARS{pdb_file}->{ATOM_chains}})){
        foreach my $chainid (@{$VARS{pdb_file}->{ATOM_chains}}){
            if (($chainid eq " " and $FORM{chain} =~ /none/i) or $chainid =~ /$FORM{chain}/i){
                $atom = $VARS{pdb_file}->get("ATOM$chainid.raw");
                last;
            }
        }
    }
    if ($seqres eq "" and $atom eq ""){
        &exit_on_error('user_error',"The protein sequence for chain '$FORM{chain}' was not found in SEQRES nor ATOM fields in the PDB file.");
    }
    # output a message in case there is no seqres relevant sequence, but there are other chains.
    if ($seqres eq "" and (defined (@{$VARS{pdb_file}->{SEQRES_chains}}))){
        my $all_chains = "";
        foreach my $chainid (@{$VARS{pdb_file}->{SEQRES_chains}}){
           if ($chainid eq " ") {$chainid = "NONE";}
           $all_chains.= "$chainid, ";
        }
        chop($all_chains);
        chop($all_chains);
        if ($FORM{chain} =~ /NONE/i){
            exit_on_error('user_error',"The chain column in SEQRES field is not empty, but contains the chains: $all_chains. Please check the <a href = \"$VARS{pdb_file_name}\">PDB file</a>, or run ConSurf again with a specific chain identifier.");
        }
        else{
            exit_on_error('user_error',"Chain \"$FORM{chain}\" does not exist in the SEQRES field of the PDB file $VARS{pdb_file_name}.\nPlease check your file or run ConSurf again with a different chain. If there is no chain identifier, choose \"NONE\" as your Chain Identifier.");
        }
    }
    return ($seqres,$atom);
}
#---------------------------------------------
sub create_MSA{
#---------------------------------------------
    my $cmd;
    chdir $VARS{working_dir};
    if($FORM{MSAprogram} eq 'CLUSTALW'){
        $cmd = CONSURF_CONSTANTS::CLUSTALW." -infile=$VARS{FINAL_sequences} -outfile=$VARS{protein_MSA}";
    }
    else{
        $cmd = CONSURF_CONSTANTS::MUSCLE." -in $VARS{FINAL_sequences} -out $VARS{protein_MSA} -clwstrict -quiet";
    }
    print LOG "create_MSA : run $cmd\n";
    chdir $VARS{working_dir};
    `$cmd`;
    if (!-e "$VARS{working_dir}/$VARS{protein_MSA}" or -z "$VARS{working_dir}/$VARS{protein_MSA}"){
        exit_on_error('sys_error',"create_MSA : the file $VARS{working_dir}/$VARS{protein_MSA} was not created or of size zero");
    }
    $VARS{msa_format} = "clustalw";
    # remove the dnd file    
    $cmd = "rm *.dnd";
    chdir $VARS{working_dir};
    `$cmd`;
}
#---------------------------------------------
sub open_log_file{
#---------------------------------------------
    if (!-e $VARS{run_log} or -z $VARS{run_log}){
        open LOG, ">".$VARS{run_log} or exit_on_error('sys_error', "Cannot open the log file $VARS{run_log} for writing $!");
        print LOG "--------- ConSurf Log $VARS{run_log}.log -------------\n";
        print LOG "Begin Time: ".CONSURF_FUNCTIONS::printTime()."\n";
    }
    else{
        open LOG, ">>".$VARS{run_log} or exit_on_error('sys_error', "Cannot open the log file $VARS{run_log} for writing $!");
    }
}
#---------------------------------------------
sub exit_on_error{
#---------------------------------------------
    my $which_error = shift;
    my $error_msg = shift;
    
    if ($which_error eq 'user_error'){
        print LOG "\nEXIT on error:\n$error_msg\n";
        print "\nEXIT on error:\n$error_msg\n";
        # print $error_msg to the screen
    }
    elsif($which_error eq 'sys_error'){
        print LOG "\n$error_msg\n";
        #print $error_msg to the log file
	print "\n$error_msg\n";
    }    
    print LOG "\nExit Time: ".(CONSURF_FUNCTIONS::printTime)."\n";
    close LOG;
    exit;
}
#---------------------------------------------
sub run_rate4site{    
#---------------------------------------------  
    my ($cmd, $algorithm, $tree_file_r4s, $query_name, $msa, $did_r4s_fail);    
    my %MatrixHash = (JTT => '-Mj', mtREV => '-Mr', cpREV => '-Mc', WAG => '-Mw', Dayhoff => '-Md');
    # choose the algorithm
    if ($FORM{algorithm} eq "LikelihoodML"){
        $algorithm = "-im";
    }
    else{
        $algorithm = "-ib";
    }
    $tree_file_r4s = '';
    if ($VARS{running_mode} eq "_mode_pdb_msa_tree" or $VARS{running_mode} eq "_mode_msa_tree"){
        $tree_file_r4s = "-t $VARS{user_tree_file_name}";
    }
    if ($VARS{running_mode} eq "_mode_pdb_no_msa" or $VARS{running_mode} eq "_mode_no_pdb_no_msa"){
        $query_name = $VARS{query_string};
        $msa = $VARS{protein_MSA};
        $VARS{rate4site_msa_format} = "clustalw";
    }
    else{
        $query_name = $FORM{msa_SEQNAME};
        print LOG "run_rate4site : Please note: MSA for rate4site run is '$VARS{user_msa_fasta}' (and not original user file : '$VARS{user_msa_file_name}')\n";
        $msa = $VARS{user_msa_fasta};
        $VARS{rate4site_msa_format} = "fasta";
    }
    my $r4s_comm = "$rate4s $algorithm -a \'$query_name\' -s $msa -zn $MatrixHash{$FORM{matrix}} $tree_file_r4s -bn -l $VARS{r4s_log} -o $VARS{r4s_out}";
    if ($tree_file_r4s eq ""){$r4s_comm = $r4s_comm." -x $VARS{r4s_tree}";}
    print LOG "run_rate4site : running command: $r4s_comm\n";
    chdir $VARS{working_dir};
    `$r4s_comm`;
    $did_r4s_fail = &check_if_rate4site_failed("$VARS{working_dir}/$VARS{r4s_out}", "$VARS{working_dir}/$VARS{r4s_log}");
    # if the run failed - we rerun using the slow verion
    if ($did_r4s_fail eq "yes"){
        print LOG "run_rate4site : The run of rate4site failed. Sending warning message to output.\nThe same run will be done using the SLOW version of rate4site.\n";
        print_message_to_output("Warning: The given MSA is very large, therefore it will take longer for ConSurf calculation to finish. The calculation continues nevertheless.");
        $r4s_comm = "$rate4s $algorithm -a \'$query_name\' -s $msa -zn $MatrixHash{$FORM{matrix}} $tree_file_r4s -bn -l $VARS{r4s_slow_log} -o $VARS{r4s_out}";
	if ($tree_file_r4s eq ""){$r4s_comm = $r4s_comm." -x $VARS{r4s_tree}";}
        print LOG "run_rate4site : running command: $r4s_comm\n";
        chdir $VARS{working_dir};
        `$r4s_comm`;
        $did_r4s_fail = &check_if_rate4site_failed("$VARS{working_dir}/$VARS{r4s_out}", "$VARS{working_dir}/$VARS{r4s_slow_log}");
        if ($did_r4s_fail eq "yes"){            
            my $err = "The run $r4s_comm for $VARS{run_number} failed.\nThe MSA $msa was too large.\n";
            exit_on_error('user_error', "The calculation could not be completed due to memory problem, since the MSA is too large. Please run ConSurf again with fewer sequences.")
        }
    }    
}
#---------------------------------------------    
sub check_if_rate4site_failed{
# There are some tests to see if rate4site failed.
# Since I can't trust only one of them, I do all of them. If onw of them is tested to be true - than a flag will get TRUE value
# 1. the .res file might be empty.
# 2. if the run failed, it might be written to the log file of r4s.
# 3. in a normal the r4s.log file there will lines that describe the grades. if it fail - we won't see them
# In one of these cases we try to run the slower version of rate4site.
# We output this as a message to the user.
#---------------------------------------------
    my ($res_flag, $r4s_log) = @_;
    my $ret = "no";
    my @did_r4s_failed = &CONSURF_FUNCTIONS::check_if_rate4site_failed($res_flag, $r4s_log);    
    if ($did_r4s_failed[0] eq "yes"){
        $ret = "yes";
        print LOG "check_if_rate4site_failed : ".$did_r4s_failed[1];
        $VARS{r4s_process_id} = $did_r4s_failed[2];        
        &remove_core();
        # if there was an error in user input which rate4site reported: we output a message to the user and exit
        if (exists $did_r4s_failed[3] and $did_r4s_failed[3] ne ""){
            exit_on_error('user_error', $did_r4s_failed[3])
        }
    }
    return $ret;
}
#---------------------------------------------
sub print_message_to_output{
#---------------------------------------------
    my $msg = shift;
    print "\n$msg\n";
}
#---------------------------------------------
sub remove_core{
#---------------------------------------------
    if (-e "$VARS{working_dir}/core.$VARS{r4s_process_id}"){
        print LOG "remove core file : core.".$VARS{r4s_process_id}."\n";
        unlink "$VARS{working_dir}/core.$VARS{r4s_process_id}";
    }
}
#---------------------------------------------
sub assign_colors_according_to_r4s_layers{
#---------------------------------------------
    my $ref_to_gradesPE = shift;
    print LOG "assign_colors_according_to_r4s_layers : $VARS{working_dir}/$VARS{r4s_out}\n";
    my @ans = CONSURF_FUNCTIONS::assign_colors_according_to_r4s_layers("$VARS{working_dir}/$VARS{r4s_out}", $ref_to_gradesPE);
    if ($ans[0] ne "OK") {
        exit_on_error('sys_error',$ans[0]);}
}
#---------------------------------------------
sub read_residue_variety{
#---------------------------------------------
    my ($ref_to_res_freq, $ref_to_positionAA) = @_;
    print LOG "read_residue_variety : Calling: MSA_parser::read_residue_variety($VARS{working_dir}/$VARS{protein_MSA}, $VARS{query_string}, $VARS{rate4site_msa_format}, $ref_to_res_freq, $ref_to_positionAA)\n";
    my @ans = MSA_parser::read_residue_variety("$VARS{working_dir}/$VARS{protein_MSA}", $VARS{query_string}, $VARS{rate4site_msa_format}, $ref_to_res_freq, $ref_to_positionAA);
    if ($ans[0] ne "OK") {
        exit_on_error('sys_error',$ans[0]);}
    if (keys %$ref_to_res_freq<1 or (keys %$ref_to_positionAA <1)){
        exit_on_error('sys_error',"could not extract information from MSA $VARS{protein_MSA} in routine MSA_parser::read_residue_variety");}
    
    $VARS{num_of_seqs_in_MSA} = $ans[1];    
}
#---------------------------------------------
sub create_atom_position_file{
#---------------------------------------------
    my $chain;
    unless ($FORM{chain} =~ /none/i){
        $chain = $FORM{chain};}
    else{
        $chain = " ";}
    my %output;
    print LOG "create_atom_position_file : calling CONSURF_FUNCTIONS::create_atom_position_file($VARS{pdb_file_name},$VARS{working_dir}/$VARS{atom_positionFILE},$chain,\%output)\n";
    CONSURF_FUNCTIONS::create_atom_position_file("$VARS{pdb_file_name}","$VARS{working_dir}/$VARS{atom_positionFILE}", $chain, \%output);
    #rasmol_gradesPE_and_pipe::create_atom_position_file("$VARS{pdb_file_name}","$VARS{working_dir}/$VARS{atom_positionFILE}", $chain, \%output);
    if (exists $output{ERROR}) {exit_on_error('sys_error',$output{ERROR});}	
	if (exists $output{INFO}) {print LOG "create_atom_position_file : $output{INFO}";}
	if (exists $output{WARNING}) {print LOG "create_atom_position_file : $output{WARNING}";}
    if (!-e "$VARS{working_dir}/$VARS{atom_positionFILE}" or -z "$VARS{working_dir}/$VARS{atom_positionFILE}"){
        exit_on_error('sys_error',"create_atom_position_file : The file $VARS{working_dir}/$VARS{atom_positionFILE} does not exist or of size 0");
    }
}
#---------------------------------------------
sub match_pdb_to_seq{
#---------------------------------------------    
    my $ref_r4s2pdb = shift;
    my $chain;
    unless ($FORM{chain} =~ /none/i){
        $chain = $FORM{chain};}
    else{
        $chain = " ";}
    print LOG "match_pdb_to_seq : CONSURF_FUNCTIONS::match_seqres_pdb($VARS{working_dir}/$VARS{pairwise_aln}, $VARS{working_dir}/$VARS{atom_positionFILE}, $chain, $ref_r4s2pdb)\n";
    my @ans = CONSURF_FUNCTIONS::match_seqres_pdb("$VARS{working_dir}/$VARS{pairwise_aln}", "$VARS{working_dir}/$VARS{atom_positionFILE}", $chain, $ref_r4s2pdb);
    unless ($ans[0] eq "OK") {exit_on_error('sys_error', "match_pdb_to_seq : CONSURF_FUNCTIONS::".$ans[0]);}
    elsif (keys %$ref_r4s2pdb <1 ){exit_on_error('sys_error',"match_pdb_to_seq : Did not create hash to hold r4s and ATOM sequences");}
    print LOG "match_pdb_to_seq : Total residues in the msa sequence: $ans[1]. Total residues in the ATOM : $ans[2]\n";
    $length_of_seqres = $ans[1];
    $length_of_atom = $ans[2];
  
}
#---------------------------------------------
sub create_gradesPE(){
#---------------------------------------------
    my $ref_r4s2pdb = shift;
    my @ans=CONSURF_FUNCTIONS::create_gradesPE(\@gradesPE_Output, $ref_r4s2pdb, \%residue_freq, \@no_isd_residue_color, \@isd_residue_color, "$VARS{working_dir}/$VARS{gradesPE}");
    unless ($ans[0] eq "OK"){exit_on_error('sys_error', "create_gradesPE : CONSURF_FUNCTION::".$ans[0]);}
    elsif(!-e "$VARS{working_dir}/$VARS{gradesPE}" or -z "$VARS{working_dir}/$VARS{gradesPE}") {
        exit_on_error('sys_error', "create_gradesPE : the file $VARS{working_dir}/$VARS{gradesPE} was not found or empty");}
    if ($ans[1] eq "" or $ans[2] eq ""){
        exit_on_error('sys_error', "create_gradesPE : there is no data in the returned values seq3d_grades_isd or seq3d_grades from the routine");
    }
    $seq3d_grades_isd = $ans[1];
    $seq3d_grades = $ans[2];
}



#-------------------------------------------
sub Print_Help(){
#-------------------------------------------
print <<EndOfHelp;
           ConSurf - Identification of Functional Regions in Proteins
=========================================================================================
Usage
=#=#=#=#	
The ConSurf work in several modes
1. Given Protein PDB File.
2. Given Multiple Sequence Alignment (MSA) and Protein PDB File.
3. Given Multiple Sequence Alignment (MSA), Phylogenetic Tree, and PDB File.

The script is using the user provided MSA (and Phylogenetic tree if available) to calculate the conservation score for each position in the MSA based on the Rate4Site algorithm (Mayrose, I., Graur, D., Ben-Tal, N., and Pupko, T. 2004. Comparison of site-specific rate-inference methods: Bayesian methods are superior. Mol Biol Evol 21: 1781-1791).

When running in the first mode the scripts the MSA is automatically build the MSA for the given protein based on ConSurf protocol.

Usage: ConSurf -PDB <PDB FILE FULL PATH>  -CHAIN <PDB CHAIN ID> -Out_Dir <Output Directory>


MANDATORY INPUTS
==============================
-PDB <PDB FILE FULL PATH> - PDB File
-CHAIN <PDB CHAIN ID> - Chain ID
-Out_Dir <Output Directory> - Output Path

MSA Mode (Not Using -m)
================================
-MSA <MSA File Name>	(MANDATORY IF -m NOT USED)
-SEQ_NAME <"Query sequence name in MSA file">  (MANDATORY IF -m NOT USED)
-Tree <Phylogenetic Tree (in Newick format)> (optional, default building tree by Rate4Site).

Building MSA (Using -m)
===============================
-m       		Builed MSA mode
	-MSAprogram ["CLUSTALW"] or ["MUSCLE"] (default: MUSCLE)		
	-DB ["SWISS-PROT"] or ["UNIPROT"] (default: UniProt)  
	-MaxHomol <Max Number of Homologs to use for ConSurf Calculation> (deafult: 50)
	-Iterat <Number of PsiBlast iterataion> (default: 1)
	-ESCORE <Minimal E-value cutoff for Blast search> (default: 0.001)
	

Rate4Site Parameter (see http://consurf.tau.ac.il/overview.html#methodology and http://consurf.tau.ac.il/overview.html#MODEL for detains)
===========================================================================================================================================
-Algorithm [LikelihoodML] or [Bayesian] (default: Bayesian)
-Matrix [JTT] or [mtREV] or [cpREV] or [WAG] or [Dayhoff] (default JTT)

Help Me!!
=============
-h - Shows this help screen

Examples:
1. Basic Build MSA mode (using defaults parameters) 
	perl ConSurf.pl -PDB  MY_PDB_FILE.pdb -CHAIN MY_CHAIN_ID -Out_Dir /MY_DIR/ -m
2. using build MSA mode and advanced options: 
	perl ConSurf.pl -PDB MY_PDB.pdb -CHAIN A -Out_Dir /MY_DIR/ -m -MSAprogram CLUSTALW -DB "SWISS-PROT" -MaxHomol 100 -Iterat 2 -ESCORE 0.00001 -Algorithm LikelihoodML -Matrix Dayhoff
		Will run Consurf in: building MSA mode (-m) for Chain A (-CHAIN) of PDB file: /groups/bioseq.home/1ENV.pdb (-PDB). The sequences for the MSA will be chosen according 2  iterations of PSI-Blast (-Iterat) against SwissProt Database (-DB "SWISS-PROT"), with E value cutoff of 0.00001 (-ESCORE), considering maximum 100 homologues (MaxHomol). The Rate4Site will use Maximum Liklihood algorithm (-Algorithm) and Dayhoff model (-Matrix)
3. Simple Run With prepared MSA. 
	perl ConSurf.pl -PDB MY_PDB_FILE.pdb -CHAIN A -Out_Dir /MY_DIR/ -MSA MY_MSA_FILE -SEQ_NAME MY_SEQ_NAME	

EndOfHelp
print "For any questions or suggestions please contact us: bioSequence\@tauex.tau.ac.il\n";

}

### FOR HERE ON ITS FOR LOCAL USE ONLY - NOT FOR RELEASE

#---------------------------------------------
sub create_rasmol(){
# print 2 rasmol files, one showing insufficient data, one hiding it.
#---------------------------------------------
    my $chain;
    unless ($FORM{chain} =~ /none/i){
        $chain = $FORM{chain};}
    else{
        $chain = " ";}
    my @ans;
    print LOG "Calling cp_rasmol_gradesPE_and_pipe::print_rasmol for files $VARS{working_dir}/$VARS{rasmolFILE} and $VARS{working_dir}/$VARS{rasmol_isdFILE}\n";
    @ans = cp_rasmol_gradesPE_and_pipe::print_rasmol("$VARS{working_dir}/$VARS{rasmolFILE}", "no",\@no_isd_residue_color, $chain, "no"); #Without isd residue Color
    unless ($ans[0] eq "OK") {
        exit_on_error('sys_error', "create_rasmol : cp_rasmol_gradesPE_and_pipe::$ans[0]");
        }
    @ans = cp_rasmol_gradesPE_and_pipe::print_rasmol("$VARS{working_dir}/$VARS{rasmol_isdFILE}", "yes",\@isd_residue_color, $chain, "no");#With isd Residue Color
    unless ($ans[0] eq "OK") {
        exit_on_error('sys_error', "create_rasmol : cp_rasmol_gradesPE_and_pipe::$ans[0]");
        }
    if (!-e "$VARS{working_dir}/$VARS{rasmolFILE}" or -z "$VARS{working_dir}/$VARS{rasmolFILE}" or !-e "$VARS{working_dir}/$VARS{rasmol_isdFILE}"  or -z "$VARS{working_dir}/$VARS{rasmol_isdFILE}") {
    exit_on_error('sys_error', "create_rasmol : Did not create one of rasmol outputs");
    }
}
#---------------------------------------------
 sub create_chimera (){
##---------------------------------------------
# Chimera Output includes several files:
# a. header file *.hdr
# b. scf file *.scf
# c. script to show the colored MSA, Tree, and colored 3D structure. (.chimerax)
# d. the Script for Chimera Image.
# e. The Html with the istructions how to create Chimera High resolution Image
#
# A.+B. creating the *.hdr and *.scf files	
# creating view page for the chimera alingment requires the query name for the input sequence in the MSA. In case MSA was uploaded - this name might not be exact, so the option of viewing the alignment only applies for cases where the user did not supply MSA
    print LOG "Calling: cp_rasmol_gradesPE_and_pipe::color_with_chimera($VARS{working_dir}, $VARS{msa_SEQNAME}, $VARS{protein_MSA}, $VARS{r4s_out}, $VARS{scf_for_chimera}, $VARS{header_for_chimera},$VARS{isd_scf_for_chimera},$VARS{isd_header_for_chimera})\n";
    my @ans=cp_rasmol_gradesPE_and_pipe::color_with_chimera($VARS{working_dir}, $VARS{msa_SEQNAME}, $VARS{protein_MSA}, $VARS{r4s_out}, $VARS{scf_for_chimera}, $VARS{header_for_chimera},$VARS{isd_scf_for_chimera},$VARS{isd_header_for_chimera});
    
    if ($ans[0] ne "OK") {exit_on_error('sys_error', "create_chimera: @ans\n");}
    else {$VARS{insufficient_data}=$ans[1];}
    
# C. creating the script that shows the MSA, Tree and colored 3D structure 
	print LOG "Calling: cp_rasmol_gradesPE_and_pipe::create_chimera_script ($VARS{ATOMS_with_ConSurf_Scores},$VARS{run_url}, $VARS{working_dir}, $VARS{chimerax_file},$VARS{protein_MSA},$VARS{tree_file},$VARS{scf_for_chimera}, $VARS{header_for_chimera})\n";
	cp_rasmol_gradesPE_and_pipe::create_chimera_script ($VARS{ATOMS_with_ConSurf_Scores},$VARS{run_url}, $VARS{working_dir}, $VARS{chimerax_file},$VARS{protein_MSA},$VARS{tree_file},$VARS{scf_for_chimera}, $VARS{header_for_chimera});

	# create also ignoring insufficient data file, only in case the selected algorithm was bayes
	if ($VARS{insufficient_data} eq "yes" and $FORM{algorithm} eq "Bayes")
	{
		print LOG "Calling: cp_rasmol_gradesPE_and_pipe::create_chimera_script ($VARS{ATOMS_with_ConSurf_Scores_isd}, $VARS{run_url}, $VARS{working_dir}, $VARS{isd_chimerax_file},$VARS{protein_MSA},$VARS{tree_file},$VARS{isd_scf_for_chimera}, $VARS{isd_header_for_chimera})\n";
		cp_rasmol_gradesPE_and_pipe::create_chimera_script ($VARS{ATOMS_with_ConSurf_Scores_isd},$VARS{run_url}, $VARS{working_dir}, $VARS{isd_chimerax_file},$VARS{protein_MSA},$VARS{tree_file},$VARS{isd_scf_for_chimera}, $VARS{isd_header_for_chimera});
	}
# D. The Script For Chimera Image
	
	print LOG "Calling: cp_rasmol_gradesPE_and_pipe::create_chimera_image_script($VARS{chimerax_script_for_figure},$VARS{ATOMS_with_ConSurf_Scores},$VARS{run_url})\n";
	cp_rasmol_gradesPE_and_pipe::create_chimera_image_script($VARS{chimerax_script_for_figure},$VARS{ATOMS_with_ConSurf_Scores},$VARS{run_url});
	if ($VARS{insufficient_data} eq "yes")
	{
		print LOG "Calling: cp_rasmol_gradesPE_and_pipe::create_chimera_image_script($VARS{chimerax_script_for_figure_isd},$VARS{ATOMS_with_ConSurf_Scores_isd},$VARS{run_url})\n";
		cp_rasmol_gradesPE_and_pipe::create_chimera_image_script($VARS{chimerax_script_for_figure_isd},$VARS{ATOMS_with_ConSurf_Scores_isd},$VARS{run_url});		
	}
 # E. Create Chimera HTML Page	
 	if ($VARS{insufficient_data} eq "yes")
 	{
 		my @ans=cp_rasmol_gradesPE_and_pipe::create_chimera_page ("$VARS{working_dir}/$VARS{chimera_instructions}",$VARS{Confidence_link}, $VARS{chimera_color_script}, $VARS{chimerax_script_for_figure},$VARS{ATOMS_with_ConSurf_Scores}, $VARS{chimerax_script_for_figure_isd}, $VARS{ATOMS_with_ConSurf_Scores_isd});
		if ($ans[0] ne "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::create_chimera_page FAILED: @ans");}
 	}
 	else
	{
		my @ans=cp_rasmol_gradesPE_and_pipe::create_chimera_page ("$VARS{working_dir}/$VARS{chimera_instructions}",$VARS{Confidence_link}, $VARS{chimera_color_script}, $VARS{chimerax_script_for_figure},$VARS{ATOMS_with_ConSurf_Scores});
		if ($ans[0] ne "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::create_chimera_page FAILED: @ans");}
	}
# 		my $chimera_instructions_file = shift;
# 	my $chimera_consurf_commands = shift;
# 	my $conf_link= shift;
# 	
# 	my $chimerax_script = shift;
# 	my $PDB_atoms_ConSurf = shift;
# 	
# 	my $isd_PDB_atoms_ConSurf = shift;
# 	my $isd_chimerax_script =shift;
# 	
	
		
}


#---------------------------------------------
sub create_pipe_file (){
##---------------------------------------------
    # CREATE PART of PIPE	
    print LOG "Calling cp_rasmol_gradesPE_and_pipe::create_part_of_pipe_new $VARS{pipeFile},$VARS{unique_seqs},$FORM{database},seq3d_grades_isd, seq3d_grades, $length_of_seqres, $length_of_atom, $FORM{ESCORE},$FORM{iterations},$FORM{MAX_NUM_HOMOL},$FORM{MSAprogram},$FORM{algorithm},$FORM{matrix}\n";
    my @ans = cp_rasmol_gradesPE_and_pipe::create_part_of_pipe_new("partOfPipe",$VARS{unique_seqs},$FORM{database},$seq3d_grades_isd, $seq3d_grades, $length_of_seqres, $length_of_atom, \@isd_residue_color, \@no_isd_residue_color, $FORM{ESCORE},$FORM{iterations},$FORM{MAX_NUM_HOMOL},$FORM{MSAprogram},$FORM{algorithm},$FORM{matrix});
    unless ($ans[0] eq "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::create_part_of_pipe_new FAILED: @ans");}	
    elsif(!-e "partOfPipe" or -z $VARS{pipeFile}){&exit_on_error('sys_error',"create_pipe_file: The file partOfPipe was not found or empty");}

    print LOG "going to extract data from the pdb, calling: rasmol_gradesPE_and_pipe::extract_data_from_pdb(\"$VARS{pdb_file_name}\")";
    my @header_pipe = cp_rasmol_gradesPE_and_pipe::extract_data_from_pdb("$VARS{pdb_file_name}");
    if ($header_pipe[0] ne "OK"){print LOG @header_pipe;}
	
    my ($msa_filename,$tree_filename,$run_date,$completion_time,$ref_header_title,$IN_pdb_id_capital,$msa_query_seq_name);	

    #GET THE FILE NAMES VARS{user_msa_file_name}
    if ($VARS{user_msa_file_name} ne ""){$msa_filename=$VARS{user_msa_file_name};}
    else {$msa_filename="";}
    if ($VARS{user_tree_file_name}ne ""){$tree_filename=$VARS{user_tree_file_name};}
    else {$tree_filename="";}
    
    #Get msa_query_seq_name
    if ($FORM{msa_SEQNAME} ne ""){$msa_query_seq_name=$FORM{msa_SEQNAME};}
    else {$msa_query_seq_name="";}
    
   #GET THE CURRENT TIME
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
   $year += 1900;
   $mon += 1;
   $run_date = $year . '-' . $mon . '-' . $mday;
   $completion_time = $hour . ':' . $min . ':' . $sec;
   
   $VARS{Used_PDB_Name}=$FORM{pdb_ID};
   $IN_pdb_id_capital=uc($VARS{Used_PDB_Name});
   
   # FIND IDENTICAL CHAINS
   print LOG "Calling cp_rasmol_gradesPE_and_pipe::find_identical_chains_on_PDB_File($VARS{pdb_file_name},$FORM{chain})\n";	
   @ans=cp_rasmol_gradesPE_and_pipe::find_identical_chains_on_PDB_File("$VARS{pdb_file_name}",$FORM{chain});	
   unless ($ans[0] eq "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::find_identical_chains_on_PDB_File FAILED: @ans");}
   my $identical_chains=$ans[1];
    print LOG "identical_chains:$identical_chains\n";
   # USE THE CREATED PART of PIPE to CREATE ALL THE PIPE TILL THE PDB ATOMS (DELETE THE PART PIPE)
    print LOG "Calling cp_rasmol_gradesPE_and_pipe::create_consurf_pipe_new $VARS{working_dir},$IN_pdb_id_capital,$FORM{chain},\@header_pipe,$VARS{pipeFile},$identical_chains,partOfPipe,$VARS{working_dir},$VARS{run_number},$msa_filename,$msa_query_seq_name,$tree_filename,$VARS{submission_time},$completion_time,$run_date\n";	
    @ans = cp_rasmol_gradesPE_and_pipe::create_consurf_pipe_new($VARS{working_dir},$IN_pdb_id_capital,$FORM{chain},\@header_pipe,$VARS{pipeFile},$identical_chains,"partOfPipe",$VARS{working_dir},$VARS{run_number},$msa_filename,$msa_query_seq_name,$tree_filename,$VARS{submission_time},$completion_time,$run_date);
    unless ($ans[0] eq "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::create_consurf_pipe_new FAILED: @ans");}	
    # Add the PDB data to the pipe
    print LOG "Calling: cp_rasmol_gradesPE_and_pipe::add_pdb_data_to_pipe($VARS{pdb_file_name},$VARS{pipeFile})\n";
    @ans=cp_rasmol_gradesPE_and_pipe::add_pdb_data_to_pipe($VARS{pdb_file_name},$VARS{pipeFile});
    unless ($ans[0] eq "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::add_pdb_data_to_pipe FAILED: @ans");}
    	
    if (!-e $VARS{pipeFile} or -z $VARS{pipeFile}) {
    exit_on_error('sys_error', "create_pipe_file : Did not create the FGiJ output");
    }
}

#----------------------------------------------
sub stop_reload {
##---------------------------------------------
    my $OutHtmlFile = shift;
    sleep 5;
    open OUTPUT, "<$OutHtmlFile";
    flock OUTPUT, 2;
    my @output = <OUTPUT>;
    flock OUTPUT, 8;
    close OUTPUT;
    open OUTPUT, ">$OutHtmlFile";
    
    foreach my $line (@output){    
        if ($line eq "include (\"/var/www/html/ConSurf/php/templates/output_header.tpl\");\n"){
            print OUTPUT "include (\"/var/www/html/ConSurf/php/templates/output_header_no_refresh.tpl\");\n";
        }
	else
	{
	    print OUTPUT $line;
	}	
    }
    close (OUTPUT);
 }
#---------------------------------------------
sub replace_TmpFactor_Consurf {
# This Will create a File containing th ATOMS records with the ConSurf grades instead of the TempFactor column 
	my $chain;
    	unless ($FORM{chain} =~ /none/i){
        	$chain = $FORM{chain};}
    	else{
        	$chain = " ";}
	print LOG  "Calling: cp_rasmol_gradesPE_and_pipe::ReplaceTempFactConSurfScore($chain,$VARS{pdb_file_name},$VARS{working_dir}/$VARS{gradesPE},$VARS{ATOMS_with_ConSurf_Scores},$VARS{ATOMS_with_ConSurf_Scores_isd});\n";
	my @ans=cp_rasmol_gradesPE_and_pipe::ReplaceTempFactConSurfScore($chain,"$VARS{pdb_file_name}","$VARS{working_dir}/$VARS{gradesPE}",$VARS{ATOMS_with_ConSurf_Scores},$VARS{ATOMS_with_ConSurf_Scores_isd});
	unless ($ans[0] eq "OK") {&exit_on_error('sys_error',"cp_rasmol_gradesPE_and_pipe::ReplaceTempFactConSurfScore FAILED: @ans");}
}
#---------------------------------------------


