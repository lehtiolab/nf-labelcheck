#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/labelcheck
========================================================================================
 nf-core/labelcheck Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/labelcheck
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/labelcheck --mzmls '*.mzML' --tdb swissprot.fa --mods assets/tmtmods.txt -profile docker

    Mandatory arguments:
      --mzmls                       Path to mzML files
      --mzmldef                     Alternative to --mzml: path to file containing list of mzMLs 
                                    tab separated: file-tab-channel path
      --tdb                         Path to target FASTA protein database
      --isobaric VALUE              In case of isobaric, specify: tmt10plex, tmt6plex, itraq8plex, itraq4plex
      --mods                        Path to MSGF+ modification file (two examples in assets folder)
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Options:
      --activation VALUE            Specify activation protocol: hcd (DEFAULT), cid, etd for isobaric 
                                    quantification. Not necessary for other functionality.

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}


// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}


if( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  // Check outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
  // Prevent trace files to be stored on S3 since S3 does not support rolling files.
  if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_multiqc_config = Channel.fromPath(params.multiqc_config)
ch_output_docs = Channel.fromPath("$baseDir/docs/output.md")


params.name = false
params.email = false
params.plaintext_email = false

params.mzmldef = false
params.isobaric = false
params.instrument = 'qe' // Default instrument is Q-Exactive
params.activation = 'hcd' // Only for isobaric quantification, not for ID with MSGF
params.outdir = 'results'


// Validate and set file inputs
plextype = params.isobaric ? params.isobaric.replaceFirst(/[0-9]+plex/, "") : 'false'
mods = file(params.mods)
if( !mods.exists() ) exit 1, "Modification file not found: ${params.mods}"
tdb = file(params.tdb)
if( !tdb.exists() ) exit 1, "Target fasta DB file not found: ${params.tdb}"

output_docs = file("$baseDir/docs/output.md")

// set constant variables
accolmap = [peptides: 12]


// Header log info
log.info nfcoreHeader()
def summary = [:]
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName

summary['mzMLs or input definition']        = params.mzmldef ? params.mzmldef : params.mzmls
summary['Target DB']    = params.tdb
summary['Modifications'] = params.mods
summary['Instrument'] = params.instrument
summary['Isobaric tags'] = params.isobaric
summary['Isobaric activation'] = params.activation

summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if(workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if(workflow.profile == 'awsbatch'){
   summary['AWS Region']    = params.awsregion
   summary['AWS Queue']     = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if(params.config_profile_description) summary['Config Description'] = params.config_profile_description
if(params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if(params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if(params.email) {
  summary['E-mail Address']  = params.email
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "\033[2m----------------------------------------------------\033[0m"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-labelcheck-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/labelcheck Workflow Summary'
    section_href: 'https://github.com/nf-core/labelcheck'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}


/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
    saveAs: {filename ->
        if (filename.indexOf(".csv") > 0) filename
        else null
    }

    output:
    file 'software_versions_mqc.yaml' into software_versions_yaml
    file "software_versions.csv"

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    msgf_plus | head -n1 > v_msgf.txt
    percolator -h |& head -n1 > v_perco.txt || true
    msspsmtable --version > v_mss.txt
    source activate openms-2.4.0
    IsobaricAnalyzer |& grep Version > v_openms.txt || true
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

if (params.mzmldef) {
  Channel
    .from(file("${params.mzmldef}").readLines())
    .map { it -> it.tokenize('\t') }
    .map { it -> [it[1], file(it[0])] }
    .map { it -> ["${it[0]}_${it[1].baseName.replaceFirst(/.*\/(\S+)\.mzML/, "\$1")}", it[1]] }
    .set { mzml_in }
} else {
  Channel
    .fromPath(params.mzmls)
    .map { it -> ["${it.baseName.replaceFirst(/.*\/(\S+)\.mzML/, "\$1")}", it] }
    .set { mzml_in }
}


mzml_in
  .tap { mzml_msgf; mzml_quant; sets }
  .toList()
  .map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on sample for consistent .sh script in -resume
  .map { it -> [it.collect() { it[0] }, it.collect() { it[1] } ] } // lists: [sets], [mzmlfiles]
  .set{ mzmlfiles_all }

// Set names are first item in input lists, collect them for PSM tables and QC purposes
sets
  .map{ it -> it[0] }
  .unique()
  .tap { setnames_psm } 
  .collect()
  .map { it -> [it] }
  .into { setnames_featqc; setnames_psmqc }


process quantifySpectra {

  // sample is setname in labelchecks!
  input:
  set val(setname), file(infile) from mzml_quant

  output:
  set val(setname), file("${infile}.consensusXML") into isobaricxml

  script:
  activationtype = [hcd:'High-energy collision-induced dissociation', cid:'Collision-induced dissociation', etd:'Electron transfer dissociation'][params.activation]
  massshift = [tmt:0.0013, itraq:0.00125, false:0][plextype]
  """
  source activate openms-2.4.0
  IsobaricAnalyzer  -type $params.isobaric -in $infile -out \"${infile}.consensusXML\" -extraction:select_activation \"$activationtype\" -extraction:reporter_mass_shift $massshift -extraction:min_precursor_intensity 1.0 -extraction:keep_unannotated_precursor true -quantification:isotope_correction true
  """
}


process createSpectraLookup {

  input:
  set val(setnames), file(mzmlfiles) from mzmlfiles_all

  output:
  file 'mslookup_db.sqlite' into speclookup 

  script:
  """
  msslookup spectra -i ${mzmlfiles.join(' ')} --setnames ${setnames.join(' ')}
  """
}


// Collect all isobaric quant XML output for quant lookup building process
isobaricxml
  .toList()
  .map { it.sort({a, b -> a[0] <=> b[0]}) }
  .map { it -> it.collect() { it[1] } }
  .set { isofiles_sorted }


process quantLookup {

  input:
  file lookup from speclookup
  file(isofns) from isofiles_sorted

  output:
  file 'db.sqlite' into quantlookup

  script:
  """
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat $lookup > db.sqlite
  msslookup isoquant --dbfile db.sqlite -i ${isofns.join(' ')} --spectra ${isofns.collect{ x -> x.baseName.replaceFirst(/\.consensusXML/, "")}.join(' ')}
    """
}


process createTargetDecoyFasta {
 
  input:
  file(tdb)

  output:
  file('db.fa') into concatdb
  set file(tdb), file("decoy_${tdb}") into searchdbs 

  script:
  """
  tryprev.py $tdb
  cat $tdb decoy_${tdb} > db.fa
  """
}


process msgfPlus {
  cpus = config.poolSize < 2 ? config.poolSize : 2

  input:
  set val(setname), file(x) from mzml_msgf
  file(db) from concatdb
  file mods

  output:
  set val(setname), val(sample), file("${setname}.mzid") into mzids
  set val(setname), file("${setname}.mzid"), file('out.mzid.tsv') into mzidtsvs
  
  script:
  sample = x.baseName.replaceFirst(/\.mzML/, "")
  // FIXME which protocol, ask someone
  msgfprotocol = 0 //[tmt:4, itraq:2, false:0][plextype]
  msgfinstrument = [velos:1, qe:3, false:0][params.instrument]
  """
  msgf_plus -Xmx8G -d $db -s $x -o "${setname}.mzid" -thread 2 -mod $mods -tda 0 -t 10.0ppm -ti -1,2 -m 0 -inst ${msgfinstrument} -e 1 -protocol ${msgfprotocol} -ntt 2 -minLength 7 -maxLength 50 -minCharge 2 -maxCharge 6 -n 1 -addFeatures 1
  msgf_plus -Xmx3500M edu.ucsd.msjava.ui.MzIDToTsv -i "${setname}.mzid" -o out.mzid.tsv
  rm ${db.baseName.replaceFirst(/\.fasta/, "")}.c*
  """
}

// in case we have multiple files per set in the future (you never know), we group by set
mzids
  .groupTuple()
  .set { mzids_2pin }


process percolator {

  input:
  set val(setname), val(samples), file('mzid?') from mzids_2pin

  output:
  set val(setname), file('perco.xml') into percolated

  """
  mkdir mzids
  count=1;for sam in ${samples.join(' ')}; do ln -s `pwd`/mzid\$count mzids/\${sam}.mzid; echo mzids/\${sam}.mzid >> metafile; ((count++));done
  msgf2pin -o percoin.xml -e trypsin -P "decoy_" metafile
  percolator -j percoin.xml -X perco.xml -N 500000 --decoy-xml-output -y
  """
}


mzidtsvs
  .groupTuple()
  .join(percolated)
  .set { mzperco }


process svmToTSV {

  input:
  set val(setname), file('mzident????'), file('mzidtsv????'), file(perco) from mzperco 

  output:
  set val(setname), file('tmzidperco') into tmzidtsv_perco

  script:
  """
  perco_to_tsv.py -p $perco 
  """
}

// Collect percolator data of target and feed into PSM table creation
tmzidtsv_perco
  .toList()
  .map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on setname for resumable PSM table
  .map { it -> [it.collect() { it[0]}, it.collect() { it[1] }] }
  .combine(quantlookup)
  .set { prepsm }



/*
* Step 3: Post-process peptide identification data
*/
process createPSMTable {

  input:
  set val(setnames), file('psms?'), file('lookup') from prepsm
  file(tdb)

  output:
  file("${outpsms}") into psm_result
  set val({setnames.collect() { it }}), file({setnames.collect() { it + '.tsv' }}) into setpsmtables
  

  script:
  psmlookup = "psmlookup.sql"
  outpsms = "psmtable.txt"
  """
  msspsmtable merge -i psms* -o psms.txt
  msspsmtable conffilt -i psms.txt -o filtpsm --confidence-better lower --confidence-lvl 0.01 --confcolpattern 'PSM q-value'
  msspsmtable conffilt -i filtpsm -o filtpep --confidence-better lower --confidence-lvl 0.01 --confcolpattern 'peptide q-value'
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat lookup > $psmlookup
  msslookup psms -i filtpep --dbfile $psmlookup 
  msspsmtable specdata -i filtpep --dbfile $psmlookup -o prepsms.txt
  msspsmtable quant -i prepsms.txt -o "${outpsms}" --dbfile $psmlookup --isobaric
  sed 's/\\#SpecFile/SpectraFile/' -i "${outpsms}"
  msspsmtable split -i "${outpsms}" --bioset
  """
}

setpsmtables
  .map { it -> [it[0], it[1]] }
  .transpose()
  .set { psm_pep }

process psm2Peptides {

  input:
  set val(setname), file(psms) from psm_pep
  
  output:
  file("${setname}") into peptides_out
  stdout into psm_stats
  set val("$setname"), file("means") into psmmeans

  script:
  col = accolmap.peptides + 1  // psm2pep adds a column
  """
  # Create peptide table from PSM table, picking best scoring unique peptides
  msspeptable psm2pep -i $psms -o peptides --scorecolpattern svm --spectracol 1 --isobquantcolpattern plex 
  # Move peptide sequence to first column
  paste <( cut -f ${col} peptides) <( cut -f 1-${col-1},${col+1}-500 peptides) > "${setname}"

# FIXME 229 is TMT, also get theother ones, from the mod file!
  echo -n "$setname" \$(calc_psmstats.py $psms 'Peptide' '+229.163') \$(calc_psmstats.py "$setname" 'Peptide sequence' '+229.163') | tr ' ' '\t'
  """
}


psm_stats
  .map { it -> it.tokenize('\t') }
  .join(psmmeans)
  .toList()
  .map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on sample for consistent .sh script in -resume
  .transpose()
  .toList()
  .set { psm_values }

peptides_out
  .toList()
  .set { peptide_tables }


process reportLabelCheck {

  cache false
  publishDir "${params.outdir}", mode: 'copy'

  input:
  file('peps*') from peptide_tables
  set val(setnames), val(ok_psms), val(fail_psms), val(ok_pep), val(fail_pep), file('means*') from psm_values
  file(psms) from psm_result

  output:
  file('qc.html') into results

  script:
  """
#!/usr/bin/env python 
  
from glob import glob
import json
from jinja2 import Template
  
setnames = ["${setnames.join('", "')}"]
sorted_setnames = ${params.mzmldef ? "sorted(setnames, key=lambda x: (x.split('_')[1:], x.split('_')[0].replace('N', 'A')))" : "setnames"} # sort on N/C if channels
sorted_setnames_order = [setnames.index(x) for x in sorted_setnames]
labeldata = [{'feat': 'psm', 'label': 'labeled', 'data': $ok_psms}, {'feat': 'pep', 'label': 'labeled', 'data': $ok_pep}, {'feat': 'psm', 'label': 'non-labeled', 'data': $fail_psms}, {'feat': 'pep', 'label': 'non-labeled', 'data': $fail_pep}]
for ld in labeldata:
    ld['data'] = [ld['data'][ix] for ix in sorted_setnames_order]

tmtmeans = {}
meanfns = sorted(glob('means*'), key=lambda x: int(x[x.index('ns')+2:]))
for ix in sorted_setnames_order:
    with open(meanfns[ix]) as fp:
        for ch,val in json.load(fp).items():
            try:
                tmtmeans[ch].append(val)
            except KeyError:
                tmtmeans[ch] = [val]
    
with open("${baseDir}/assets/report.html") as fp: 
    main = Template(fp.read())
with open('qc.html', 'w') as fp:
    fp.write(main.render(setnames=sorted_setnames, labeldata=labeldata, tmtmeans=tmtmeans))
"""
}


/*
 * STEP 3 - Output Description HTML
 */
process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    file output_docs from ch_output_docs

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.r $output_docs results_description.html
    """
}



/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/labelcheck] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[nf-core/labelcheck] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if(workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp


    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/labelcheck] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[nf-core/labelcheck] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/pipeline_info/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCountFmt > 0 && workflow.success) {
      log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
      log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCountFmt} ${c_reset}"
      log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCountFmt} ${c_reset}"
    }

    if(workflow.success){
        log.info "${c_purple}[nf-core/labelcheck]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[nf-core/labelcheck]${c_red} Pipeline completed with errors${c_reset}"
    }

}


def nfcoreHeader(){
    // Log colors ANSI codes
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";

    return """    ${c_dim}----------------------------------------------------${c_reset}
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  nf-core/labelcheck v${workflow.manifest.version}${c_reset}
    ${c_dim}----------------------------------------------------${c_reset}
    """.stripIndent()
}

def checkHostname(){
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if(params.hostnames){
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if(hostname.contains(hname) && !workflow.profile.contains(prof)){
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}
