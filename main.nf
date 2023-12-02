#!/usr/bin/env nextflow
/*
========================================================================================
                         lehtiolab/nf-labelcheck
========================================================================================
 lehtiolab/nf-labelcheck Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/lehtiolab/nf-labelcheck
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run lehtiolab/nf-labelcheck --mzmls '*.mzML' --tdb swissprot.fa --mods assets/mods.txt -profile docker

    Mandatory arguments:
      --mzmls                       Path to mzML files
      --instrument                  When using --mzmls, specify qe, velos, qehf, qehfx, lumos, timstof, lowres
      --setname                     When using --mzmls, specify (set) name for run
      --input                       Alternative to --mzml: path to file containing list of mzMLs 
                                    tab separated: file-tab-channel path
      --tdb                         Path to target FASTA protein database
      --isobaric VALUE              In case of isobaric, specify: tmt10plex, tmt6plex, itraq8plex, itraq4plex, tmt16plex, tmt18plex
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Optional arguments:
      --sampletable                 Tab-separated file detailing the samples in the mzMLs per channel
      --mods                        Path to MSGF+ modification file (default in assets folder)
      --activation VALUE            Specify activation filtering for isobaric quant: auto (DEFAULT, hcd/hcid), 
                                    hcd, cid, etd, or any (no filter)
                                    quantification. Not necessary for other functionality.
      --maxmissedcleavages          Max amount of missed cleavages to report (default 4)

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

// Show help message
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
ch_output_docs = Channel.fromPath("$baseDir/docs/output.md")


params.name = false
params.email = false
params.plaintext_email = false

params.iput = false
params.sampletable = false
params.isobaric = false
params.activation = 'auto' // Only for isobaric quantification, not for ID with MSGF
params.outdir = 'results'
params.mods = "${baseDir}/assets/mods.txt"
params.psmconflvl = 0.01
params.pepconflvl = 0.01
params.maxmissedcleavages = 2



// Validate and set inputs
if (!params.isobaric) exit 1, "Isobaric type needs to be specified"
isobaric = params.isobaric == 'tmtpro' ? 'tmt16plex': params.isobaric
plextype = isobaric.replaceFirst(/[0-9]+plex/, "")
mods = file(params.mods)
if( !mods.exists() ) exit 1, "Modification file not found: ${params.mods}"
tdb = file(params.tdb)
if( !tdb.exists() ) exit 1, "Target fasta DB file not found: ${params.tdb}"

maxmiscleav = params.maxmissedcleavages > -1 ? params.maxmissedcleavages : 1000

output_docs = file("$baseDir/docs/output.md")

// set constant variables
accolmap = [peptides: 12]
plexmap = [tmt10plex: ["TMT6plex",  229.162932],
           tmt6plex: ["TMT6plex",  229.162932],
           tmt16plex: ["TMTpro", 304.207146],
           tmt18plex: ["TMTpro", 304.207146],
           itraq8plex: ["iTRAQ8plex", 304.205360],
           itraq4plex: ["iTRAQ4plex", 144.102063],
]

// Header log info
log.info nfcoreHeader()
def summary = [:]
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName

summary['mzMLs or input definition'] = params.input ? params.input : params.mzmls
summary['Sample table'] = params.sampletable
summary['Target DB']    = params.tdb
summary['Modifications'] = params.mods
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
    id: 'nf-labelcheck-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'lehtiolab/nf-labelcheck Workflow Summary'
    section_href: 'https://github.com/lehtiolab/nf-labelcheck'
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
    msstitch --version > v_mss.txt
    echo 2.9.1 > v_openms.txt
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

pooled = false
if (params.input) {
  pooled_header = ['mzmlfile', 'instrument', 'setname']
  single_header = ['mzmlfile', 'instrument', 'setname', 'channel']
  mzmllines = file("${params.input}").readLines().collect { it.tokenize('\t') }
  if (mzmllines[0] == pooled_header) {
    pooled = true
    Channel.from(mzmllines[1..-1])
      .tap { mzml_in }
      .map { it -> it[2] } // setname
      .unique()
      .set { uni_sets }
    
  } else if (mzmllines[0] == single_header) {
    Channel.from(mzmllines[1..-1])
      .tap { mzml_channels; mzml_samples }
      .map { it[0..-2] }
      .tap { mzml_in }
      .map { it -> it[2] } // setname
      .unique()
      .set { uni_sets }

  } else {
    exit 1, 'Input file (--input) format should be in the form of a tab separated file with a header'
  } 
}

// Create mzml input: [file, filename, channels, samples]
if (params.sampletable) {
  Channel
    .from(file(params.sampletable).readLines())
      .map { it -> it.tokenize('\t') }
      // make sample table interop with ddamsproteomics
      // if any more info than set/channel/sample is entered, remove it
      .map { it -> [it[1], it[0], it[2]] }
      .groupTuple()
      .into { prechannels; presamples; input_order_sets_or_fns }
  prechannels
    .map { [it[0], it[1]] }
    .set { channels }
  presamples
    .map { [it[0], it[2]] }
    .set { samples }

} else if (!pooled) {
  mzml_channels
    .map { [file("${it[0]}.tsv").baseName, it[3]] }
    .into{ channels; input_order_sets_or_fns }
  mzml_samples
    .map { it -> [file("${it[0]}.tsv").baseName, 'NA'] }
    .set{ samples }

} else {
  uni_sets
    .map { it -> [it, 'NA'] }
    .into { channels; samples; input_order_sets_or_fns }
}



mzml_in
  .map { it -> [file(it[0]).baseName, file(it[0]), it[1], it[2]] }
  .tap { mzml_msgf; mzml_quant }
  .toList()
  .map { it.sort( {a, b -> a[1] <=> b[1]}) } // sort on sample for consistent .sh script in -resume
  // Cannot transpose because when there is only one file it flattens the list
  .map { it -> [it.collect() { it[0] }, it.collect() { it[1] }, it.collect() { it[3]} ] } // lists: [basefns], [mzmlfiles], [setnames]
  .set{ mzmlfiles_all }


process quantifySpectra {
  container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
    'https://depot.galaxyproject.org/singularity/openms:2.9.1--h135471a_1' :
    'quay.io/biocontainers/openms:2.9.1--h135471a_1'}"

  input:
  set val(filename), file(infile), val(instrument), val(setname) from mzml_quant

  output:
  set val(filename), file("${infile}.consensusXML") into isobaricxml

  script:
  activationtype = [auto: 'auto', any: 'any', hcd:'beam-type collision-induced dissociation', cid:'Collision-induced dissociation', etd:'Electron transfer dissociation'][params.activation]
  massshift = [tmt:0.0013, itraq:0.00125][plextype]
  """
  IsobaricAnalyzer  -type $isobaric -in $infile -out \"${infile}.consensusXML\" -extraction:select_activation \"$activationtype\" -extraction:reporter_mass_shift $massshift -extraction:min_precursor_intensity 1.0 -extraction:keep_unannotated_precursor true -quantification:isotope_correction true
  """
}


process createSpectraLookup {

  input:
  set val(filenames), file(mzmlfiles), val(setnames) from mzmlfiles_all

  output:
  file 'mslookup_db.sqlite' into speclookup 

  script:
  """
  msstitch storespectra --spectra ${mzmlfiles.join(' ')} --setnames ${setnames.join(' ')}
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
  msstitch storequant --dbfile db.sqlite --isobaric ${isofns.join(' ')} --spectra ${isofns.collect{ x -> x.baseName.replaceFirst(/\.consensusXML/, "")}.join(' ')}
    """
}


process createTargetDecoyFasta {
 
  input:
  file(tdb)

  output:
  file('db.fa') into concatdb

  script:
  """
  msstitch makedecoy -i "$tdb" -o decoy.fa --scramble tryp_rev --ignore-target-hits
  cat "$tdb" decoy.fa > db.fa
  """
}


process msgfPlus {
  cpus = config.poolSize < 2 ? config.poolSize : 2

  input:
  set val(filename), file(x), val(instrument), val(setname) from mzml_msgf
  file(db) from concatdb
  file mods

  output:
  set val(setname), val(filename), file("${filename}.mzid"), file("${filename}.mzid.tsv") into mzids
  
  script:
  plex = plexmap[isobaric]
  msgfprotocol = 0 //[tmt:4, itraq:2][plextype]
  msgfinstrument = [lowres:0, velos:1, qe:3, qehf: 3, false:0, qehfx:1, lumos:1, timstof:2][instrument]
  """
  # dynamically add isobaric type to mod file
  cat $mods > iso_mods
  echo ${plex[1]},*,opt,N-term,${plex[0]} >> iso_mods
  echo ${plex[1]},K,opt,any,${plex[0]} >> iso_mods
  # run search and create TSV, cleanup afterwards
  msgf_plus -Xmx8G -d $db -s $x -o "${filename}.mzid" -thread ${task.cpus * 3} -mod iso_mods -tda 0 -t 10.0ppm -ti -1,2 -m 0 -inst ${msgfinstrument} -e 1 -protocol ${msgfprotocol} -ntt 2 -minLength 7 -maxLength 50 -minCharge 2 -maxCharge 6 -n 1 -addFeatures 1 -maxMissedCleavages ${params.maxmissedcleavages}
  msgf_plus -Xmx3500M edu.ucsd.msjava.ui.MzIDToTsv -i "${filename}.mzid" -o "${filename}.mzid.tsv"
  rm ${db.baseName.replaceFirst(/\.fasta/, "")}.c*
  """
}

// in case we have multiple files per set in the future (you never know), we group by set
mzids
  .groupTuple()
  .set { mzids_2pin }


process percolator {

  input:
  set val(setname), val(filenames), path(mzids), path(tsvs) from mzids_2pin

  output:
  set val(setname), path('target.tsv') into tmzidtsv_perco

  """
  for mzid in ${mzids.collect() { "'$it'" }.join(' ')}; do echo \${mzid} >> metafile; done
  msgf2pin -o percoin.xml -e trypsin -P "decoy_" metafile
  percolator -j percoin.xml -X perco.xml -N 500000 --decoy-xml-output
  mkdir outtables
  msstitch perco2psm --perco perco.xml -i ${tsvs.collect() { "'$it'" }.join(' ')} --mzids ${mzids.collect() { "'$it'" }.join(' ')} --filtpsm 0.01 --filtpep 0.01 -d outtables
  msstitch concat -i outtables/* -o psms
  msstitch split -i psms --splitcol \$(head -n1 psms | tr '\t' '\n' | grep -n ^TD\$ | cut -f 1 -d':')
  """
}


// Collect percolator data of target and feed into PSM table creation
tmzidtsv_perco
  .toList()
  .map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on setname for resumable PSM table
  .transpose()
  .toList()
  .combine(quantlookup)
  .set { prepsm }


/*
* Step 3: Post-process peptide identification data
*/

process createPSMTable {

  input:
  set val(setnames), path('psms?'), path('lookup') from prepsm

  output:
  set val(setnames), path('*.tsv') into setpsmtables
  

  script:
  psmlookup = "psmlookup.sql"
  outpsms = "psmtable.txt"
  """
  msstitch concat -i psms* -o psms.txt
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat lookup > $psmlookup
  msstitch psmtable -i psms.txt --dbfile "$psmlookup" -o "${outpsms}" --addmiscleav --addbioset --isobaric
  sed 's/\\#SpecFile/SpectraFile/' -i "${outpsms}"
# ${pooled}
  ${pooled ? "msstitch split -i '${outpsms}' --splitcol bioset" : "msstitch split -i '${outpsms}' --splitcol 1"}
  
  """
}

if (pooled) {
  setpsmtables
    .transpose()
    .join(channels)
    .join(samples)
    .set { psm_pep }
} else {
  setpsmtables
    .transpose()
    .map { [it[1].baseName, it[1]] }
    .join(channels)
    .join(samples)
    .set { psm_pep }
}

process psm2Peptides {

  input:
  set val(set_or_fn), file(psms), val(channels), val(samples) from psm_pep
  
  output:
  file("${set_or_fn}_stats.json") into psmmeans

  script:
  col = accolmap.peptides + 1  // psm2pep adds a column
  modweight = Math.round(plexmap[isobaric][1] * 1000) / 1000
  """
  # Create peptide table from PSM table, picking best scoring unique peptides
  msstitch peptides -i $psms -o "${set_or_fn}.peps" --scorecolpattern svm --spectracol 1 --isobquantcolpattern plex --medianintensity --keep-psms-na-quant
  calc_psmstats.py "$psms" "${set_or_fn}.peps" "${set_or_fn}" "${maxmiscleav}" "+${modweight}"
${params.sampletable ? "\"${channels.join(',')}\" \"${samples.join(',')}\"" : ''}
  """
}

// Let user input channel decide order of filenames
psmmeans
  .toList()
  .transpose()
  .toList()
  .set { psmdata }

input_order_sets_or_fns
  .toList()
  .transpose()
  .toList()
 // .map { it -> [it] } // when merging to keep this a list
  .merge(psmdata)
  .set { psm_values }


process pooledReportLabelCheck {
  publishDir "${params.outdir}", mode: 'copy'

  when: pooled

  input:
  tuple val(ordered_sets), val(ordered_ch), path('means????') from psm_values

  output:
  path('qc.html')

  script:
  report = "${baseDir}/assets/pooled_report.html"
  """
#!/usr/bin/env python 
  
from glob import glob
import json
from jinja2 import Template
  
# Data parsing 
ordered_sets = [${ordered_sets.collect() { x -> "'$x'"}.join(',')}]
maxmiss = int(${maxmiscleav})
data = []
for meanfn in glob('means*'):
    with open(meanfn) as fp:
        data.append(json.load(fp))
data = {x['filename']: x for x in data}

# write to HTML template
with open("${report}") as fp: 
    main = Template(fp.read())
with open('qc.html', 'w') as fp:
    fp.write(main.render(reportname='$custom_runName', filenames=ordered_sets, labeldata=data, maxmiscleav=maxmiss + 1))
"""
}


process nonPooledReportLabelCheck {

  publishDir "${params.outdir}", mode: 'copy'

  when: !pooled

  input:
// name stats files after mzml fns for easy access FIXME
  tuple val(ordered_fns), val(ordered_ch), path('means????') from psm_values

  output:
  path('qc.html')

  script:
  report = "${baseDir}/assets/nonpooled_report.html"
  """
#!/usr/bin/env python 
  
from glob import glob
import json
from collections import defaultdict
from jinja2 import Template
  
# Data parsing 
ordered_fns = [${ordered_fns.collect() { x -> "'$x'"}.join(',')}]
ordered_chs = [${ordered_ch.collect() { x-> "'$x'"}.join(',')}]

data = []
for meanfn in sorted(glob('means*'), key=lambda x: int(x[x.index('ns')+2:])):
    with open(meanfn) as fp:
        data.append(json.load(fp))
data = {x['filename']: x for x in data}
print(data)


# collect tmt mean intensities (keep input sort order for bars)
isomeans = defaultdict(list)
for fn in ordered_fns:
    for ch, val in data[fn]['psms'].items():
        isomeans[ch].append(val)

channels = sorted([x for x in isomeans.keys()], key=lambda x: x.replace('N', 'A'))
print(channels)
    
labeldata = {
    'psms': {'labeled': [], 'nonlabeled': []},
    'peps': {'labeled': [], 'nonlabeled': []},
}
miscleav = []

# data for % labeled in input-file order
for ftype in ['peps', 'psms']:
   for fn in ordered_fns:
      labeldata[ftype]['labeled'].append(data[fn][ftype]['pass'])
      labeldata[ftype]['nonlabeled'].append(data[fn][ftype]['fail'])
      if ftype == 'psm': 
          miscleav.append(data[fn][ftype]['miscleav'])
maxmiss = int(${maxmiscleav})

# write to HTML template
with open("${report}") as fp: 
    main = Template(fp.read())
with open('qc.html', 'w') as fp:
    fp.write(main.render(reportname='$custom_runName', filenames=ordered_fns, channels=ordered_chs,
        labeldata=labeldata, isomeans=dict(isomeans), miscleav=miscleav, maxmiscleav=maxmiss))
"""
}


/*
 * STEP 3 - Output Description HTML

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

*/


/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[lehtiolab/nf-labelcheck] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[lehtiolab/nf-labelcheck] FAILED: $workflow.runName"
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
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: false]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[lehtiolab/nf-labelcheck] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[lehtiolab/nf-labelcheck] Sent summary e-mail to $params.email (mail)"
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
        log.info "${c_purple}[lehtiolab/nf-labelcheck]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[lehtiolab/nf-labelcheck]${c_red} Pipeline completed with errors${c_reset}"
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
    ${c_purple}  lehtiolab/nf-labelcheck v${workflow.manifest.version}${c_reset}
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
