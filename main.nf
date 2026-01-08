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
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run lehtiolab/nf-labelcheck --mzmls '*.mzML' --tdb swissprot.fa --mods assets/mods.txt -profile docker

    Mandatory arguments:
      --input                       Path to file containing list of mzMLs, tab separated, either:
                                       filepath -tab- instrument -tab- setname -tab- channel
                                    OR (for pooled LC):
                                       filepath -tab- instrument -tab- setname
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
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.
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



// Header log info
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
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "\033[2m----------------------------------------------------\033[0m"



process isobaricQuant {

  tag 'openms'
  container params.__containers[tag][workflow.containerEngine]

  input:
  tuple val(filename), path(infile), val(instrument), val(setname), val(isobaric), val(activationtype), val(massshift)

  output:
  tuple val(filename), path("${infile}.consensusXML")

  script:
  """
  IsobaricAnalyzer  -type $isobaric -in $infile -out \"${infile}.consensusXML\" -extraction:select_activation \"$activationtype\" -extraction:reporter_mass_shift $massshift -extraction:min_precursor_intensity 1.0 -extraction:keep_unannotated_precursor true -quantification:isotope_correction true
  """
}


process createNewSpectraLookup {

  tag 'msstitch'
  container params.__containers[tag][workflow.containerEngine]

  input:
  tuple val(filenames), path(mzmlfiles), val(setnames)

  output:
  path('mslookup_db.sqlite')

  script:
  """
  msstitch storespectra --spectra ${mzmlfiles.join(' ')} --setnames ${setnames.join(' ')}
  """
}


process quantLookup {

  tag 'msstitch'
  container params.__containers[tag][workflow.containerEngine]

  input:
  tuple path(lookup), path(isofns)

  output:
  path('db.sqlite')

  script:
  """
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat $lookup > db.sqlite
  msstitch storequant --dbfile db.sqlite --isobaric ${isofns.join(' ')} --spectra ${isofns.collect{ x -> x.baseName.replaceFirst(/\.consensusXML/, "")}.join(' ')}
    """
}


process createTargetDecoyFasta {

  tag 'msstitch'
  container params.__containers[tag][workflow.containerEngine]
 
  input:
  path(tdb)

  output:
  path('db.fa')

  script:
  """
  msstitch makedecoy -i "$tdb" -o decoy.fa --scramble tryp_rev --ignore-target-hits
  cat "$tdb" decoy.fa > db.fa
  """
}


process msgfPlus {

  input:
  tuple path(db), val(filename), path(mzml), val(instrument), val(setname), path(mods), val(plexname), val(plexmass)

  output:
  tuple val(setname), val(filename), file("${filename}.mzid"), file("${filename}.mzid.tsv")
  
  script:
  msgfprotocol = 0
  msgfinstrument = [lowres:0, velos:1, qe:3, qehf: 3, false:0, qehfx:1, lumos:1, timstof:2][instrument]
  """
  # dynamically add isobaric type to mod file
  cat $mods > iso_mods
  echo ${plexmass},*,opt,N-term,${plexname} >> iso_mods
  echo ${plexmass},K,opt,any,${plexname} >> iso_mods
  # run search and create TSV, cleanup afterwards
  msgf_plus -Xmx8G -d $db -s $mzml -o "${filename}.mzid" -thread ${task.cpus * 3} -mod iso_mods -tda 0 -t 10.0ppm -ti -1,2 -m 0 -inst ${msgfinstrument} -e 1 -protocol ${msgfprotocol} -ntt 2 -minLength 7 -maxLength 50 -minCharge 2 -maxCharge 6 -n 1 -addFeatures 1 -maxMissedCleavages ${params.maxmissedcleavages}
  msgf_plus -Xmx3500M edu.ucsd.msjava.ui.MzIDToTsv -i "${filename}.mzid" -o "${filename}.mzid.tsv"
  rm ${db.baseName.replaceFirst(/\.fasta/, "")}.c*
  """
}

process percolator {

  tag 'percolator'
  container params.__containers[tag][workflow.containerEngine]

  input:
  tuple val(setname), val(filenames), path(mzids), path(tsvs)

  output:
  tuple val(setname), path('perco.xml'), path(mzids), path(tsvs)

  script:
  """
  for mzid in ${mzids.collect() { "'$it'" }.join(' ')}; do echo \${mzid} >> metafile; done
  msgf2pin -o percoin.xml -e trypsin -P "decoy_" metafile
  percolator -j percoin.xml -X perco.xml -N 500000 --decoy-xml-output
  """
}


process percolatorToPsms {
  tag 'msstitch'
  container params.__containers[tag][workflow.containerEngine]

  input:
  tuple val(setname), path('perco.xml'), path(mzids), path(tsvs), val(psmconf), val(pepconf)

  output:
  tuple val(setname), path(outfile)

  script:
  outfile = "${setname}_target.txt"
  """
  mkdir outtables
  msstitch perco2psm --perco perco.xml -i ${tsvs.collect() { "'$it'" }.join(' ')} --mzids ${mzids.collect() { "'$it'" }.join(' ')} --filtpsm ${psmconf} --filtpep ${pepconf} -d outtables
  msstitch concat -i outtables/* -o psms
  msstitch split -i psms --splitcol \$(head -n1 psms | tr '\t' '\n' | grep -n ^TD\$ | cut -f 1 -d':')
  mv target.tsv "${outfile}"
  """
}


/*
* Step 3: Post-process peptide identification data
*/
def listify(it) {
  /* This function is useful when needing a list even when having a single item
  - Single items in channels get unpacked from a list
  - Processes expect lists. Even though it would be fine
  without a list, for single-item-lists any special characters are not escaped by NF
  in the script, which leads to errors. See:
  https://github.com/nextflow-io/nextflow/discussions/4240
  */
  return it instanceof java.util.List ? it : [it]
}


process createPSMTable {

  tag 'msstitch'
  container params.__containers[tag][workflow.containerEngine]

  publishDir "${params.outdir}", mode: 'copy',
    saveAs: {filename ->
        if (filename == outpsms) filename
        else null
    }

  input:
  tuple val(setnames), path(psms), path('lookup'), val(is_pooled)

  output:
  tuple val(setnames), path('*.tsv')
  
  script:
  psmlookup = "psmlookup.sql"
  outpsms = "psmtable.txt"
  """
  msstitch concat -i ${listify(psms).collect() {"$it"}.join(' ')} -o psms.txt
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat lookup > $psmlookup
  msstitch psmtable -i psms.txt --dbfile "$psmlookup" -o "${outpsms}" --addmiscleav --addbioset --isobaric
  sed 's/\\#SpecFile/SpectraFile/' -i "${outpsms}"
  ${is_pooled ? "msstitch split -i '${outpsms}' --splitcol bioset" : "msstitch split -i '${outpsms}' --splitcol 1"}
  """
}

process psm2Peptides {

  tag 'msstitch'
  container params.__containers[tag][workflow.containerEngine]

  input:
  tuple val(set_or_fn), file(psms), val(channels), val(samples), val(maxmiscleav), val(modweight)
  
  output:
  path("${set_or_fn}_stats.json")

  script:
  """
  # Create peptide table from PSM table, picking best scoring unique peptides
  msstitch peptides -i $psms -o "${set_or_fn}.peps" --scorecolpattern svm --spectracol 1 --isobquantcolpattern plex --medianintensity --keep-psms-na-quant
  calc_psmstats.py "$psms" "${set_or_fn}.peps" "${set_or_fn}" "${maxmiscleav}" "+${modweight}"
${params.sampletable ? "\"${channels.join(',')}\" \"${samples.join(',')}\"" : ''}
  """
}


process pooledReportLabelCheck {

  tag 'ddamsproteomics'
  container params.__containers[tag][workflow.containerEngine]

  publishDir "${params.outdir}", mode: 'copy'

  input:
  tuple val(ordered_sets), val(ordered_ch), path('means????'), val(maxmiscleav)

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

  tag 'ddamsproteomics'
  container params.__containers[tag][workflow.containerEngine]
  publishDir "${params.outdir}", mode: 'copy'

  input:
// name stats files after mzml fns for easy access FIXME
  tuple val(ordered_fns), val(ordered_ch), path('means????'), val(maxmiscleav)

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

# collect tmt mean intensities (keep input sort order for bars)
isomeans = defaultdict(list)
for fn in ordered_fns:
    for ch, val in data[fn]['psms'].items():
        isomeans[ch].append(val)

channels = sorted([x for x in isomeans.keys()], key=lambda x: x.replace('N', 'A'))

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


workflow {
  // Validate and set inputs
  if (!params.isobaric) exit 1, "Isobaric type needs to be specified"
  mods = file(params.mods)
  if( !mods.exists() ) exit 1, "Modification file not found: ${params.mods}"
  tdb = file(params.tdb)
  if( !tdb.exists() ) exit 1, "Target fasta DB file not found: ${params.tdb}"
  
  activationtype = [auto: 'auto', any: 'any', hcd:'beam-type collision-induced dissociation', cid:'Collision-induced dissociation', etd:'Electron transfer dissociation'][params.activation]
  isobaric = params.isobaric == 'tmtpro' ? 'tmt16plex': params.isobaric
  plextype = isobaric.replaceFirst(/[0-9]+plex/, "")
  massshift = [tmt:0.0013, itraq:0.00125][plextype]
  maxmiscleav = params.maxmissedcleavages > -1 ? params.maxmissedcleavages : 1000
  
  // set constant variables
  plexname_mass = [tmt10plex: ["TMT6plex",  229.162932],
             tmt6plex: ["TMT6plex",  229.162932],
             tmt16plex: ["TMTpro", 304.207146],
             tmt18plex: ["TMTpro", 304.207146],
             itraq8plex: ["iTRAQ8plex", 304.205360],
             itraq4plex: ["iTRAQ4plex", 144.102063],
  ][isobaric]
  modweight = Math.round(plexname_mass[1] * 1000) / 1000
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
        .map { it -> [it[1], it[0], it[2]] } // set, channel, sample
        .groupTuple()
        .set { channel_sample }
  
  } else if (!pooled) {
    mzml_samples
      .map { it -> [file("${it[0]}.tsv").baseName, 'NA'] }
      .set{ samples }
    mzml_channels
      .map { [file("${it[0]}.tsv").baseName, it[3]] }
      .join(samples)
      .set { channel_sample }
  
  } else {
    uni_sets
      .map { it -> [it, 'NA', 'NA'] }
      .set { channel_sample }
  }

  mzml_in
    .map { it -> [file(it[0]).baseName, file(it[0]), it[1], it[2]] }
    .tap { mzml_msgf; mzml_quant }
    .toList()
    .map { it.sort( {a, b -> a[1] <=> b[1]}) } // sort on sample for consistent .sh script in -resume
    // Cannot transpose because when there is only one file it flattens the list
    .map { it -> [it.collect() { it[0] }, it.collect() { it[1] }, it.collect() { it[3]} ] } // lists: [basefns], [mzmlfiles], [setnames]
    .set{ mzmlfiles_all }
  
  
  mzml_quant
  | map { it + [isobaric, activationtype, massshift] }
  | isobaricQuant
  | toList()
  | map { it.sort({a, b -> a[0] <=> b[0]}) }
  | map { it -> it.collect() { it[1] } }
  | set { isofiles_sorted }
  
  mzmlfiles_all
  | createNewSpectraLookup
  | combine(isofiles_sorted.toList())
  | quantLookup
  
  mods = channel.fromPath(params.mods)
  channel.fromPath(params.tdb)
  | createTargetDecoyFasta
  | combine(mzml_msgf)
  | combine(mods)
  | map { it + [plexname_mass[0], plexname_mass[1]] }
  | msgfPlus
  | groupTuple()
  | percolator
  | map { it + [params.psmconflvl, params.pepconflvl] }
  | percolatorToPsms
  | toList()
  | map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on setname for resumable PSM table
  | transpose()
  | toList()
  | combine(quantLookup.out)
  | map { it + [pooled] }
  | createPSMTable
  
  if (pooled) {
    createPSMTable.out
    | transpose()
    | set { pre_peptides }
  
  } else {
    createPSMTable.out
    | map { it[1] } 
    | flatten()
    | map { [it.baseName, it] }
    | set { pre_peptides }
  }
  
  pre_peptides
  | join(channel_sample)
  | map { it + [maxmiscleav, modweight] }
  | psm2Peptides
  | toList()
  | transpose()
  | toList()
  | set { psmdata }
  
  channel_sample
  | map { it[0..1] } // set, channels ordered
  | toList()
  | transpose()
  | toList()
  | merge(psmdata)
  | map { it + [maxmiscleav] }
  | branch { it ->
    pool: pooled == true
    nonpool: pooled == false
  } | set { psm_values }
  
  psm_values.pool
  | pooledReportLabelCheck
  
  psm_values.nonpool
  | nonPooledReportLabelCheck
  | concat(pooledReportLabelCheck.out)
  | flatten
  | subscribe { it.copyTo("${params.outdir}/${it.baseName}.${it.extension}") }
}
