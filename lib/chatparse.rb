require 'find'
require 'sqlite3'
require './corpus_info'
require 'set'
require 'treetop'
require './mor'
require './chat'
require './data_reader'

CHILDES_DIRECTORY = '/home/jmu303/Documents/childes.psy.cmu.edu/data'

VERB_DATA = DataReader.hashonkeys_load(
  './verbs-CHILDES-SWBD.csv', [:Form, :Category], :CSV
)

VERBS = {}
VERB_DATA.values.each { |x| VERBS[x[:Form]] = 1 }

AGES = Hash.new { |hash, key| hash[key] = Hash.new 0 }

MISMATCHES = File.open('mismatches.txt', 'w')

MOR_PARSER = MorParser.new
CHAT_PARSER = ChatParser.new

def to_tree(sn)
  # puts sn.struct.inspect if sn.respond_to?(:struct)
  if sn.terminal?
    sn.text_value
  elsif sn.elements.all?(&:terminal?)
    (sn.elements.map(&text_value)).join('')
  else
    extensions = sn.extension_modules[0].to_s.sub(/.*::/, '')
    elements = sn.elements.map { |x| to_tree(x) unless x.empty? }.join(' ')
    "(#{extensions} #{elements})"
  end
end

# Metadata for a CHILDES Utterance that contains information about the
# entire file.
class CHILDESUtteranceMetadata
  attr_accessor :encoding, :participants, :languages, :situation, :warnings,
                :date, :comments, :birth, :location

  def initialize(metadata)
    @encoding = ''
    @participants = {}
    @languages = []
    @situation = ''
    @warnings = []
    @date = ''
    @comments = []
    @birth = {}
    @location = ''

    metadata.each do |field|
      field.gsub!(/[\t]/, ' ')
      case field
      when /^@UTF8/ then
        @encoding = 'utf8'
      when /^@Begin/ then
      when /^@Languages:/ then
        @languages = field.gsub(/^@Languages:/, '').strip
      when /^@Participants:/ then
        participants = field.gsub(/^@Participants:/, '').split(',').map(&:strip)
        participants.each do |p|
          code, name, description = p.split.map(&:strip)
          @participants[code] = {
            Code: code, Name: name, Description: description
          }
        end
      when /^@ID:/ then
        language, corpus, code, age, sex, group, ses, role, education =
          field.gsub(/^@ID:/, '').split('|').map(&:strip)
        @participants[code] = {} if @participants[code].nil?
        @participants[code].merge!(Language: language,
                                   Corpus: corpus,
                                   Age: age,
                                   Sex: sex,
                                   Group: group,
                                   SES: ses,
                                   Role: role,
                                   Education: education)
      when /^@Media:/ then # TODO: is this skipping?
      when /^@Situation:/ then
        @situation = field.gsub(/^@Situation:/, '').strip
      when /^@Warning:/ then
        @warnings = @warnings.push(field.gsub(/^@Warning:/, '').strip)
      when /^@Date:/ then
        @situation = field.gsub(/^@Situation:/, '').strip
      when /^@Comment:/ then
        @comments = @comments.push(field.gsub(/^@Comment:/, '').strip)
      when /^@Tape Location:/ then
      when /^@G:/ then
      when /^@Birth of (...):/ then
        @birth[$1] = field.gsub(/^@Birth of (...):/, '').strip
      when /^@Time Start:/ then
      when /^@Location:/ then
        @location = field.gsub(/^@Location:/, '').strip
      when /^@Activities:/ then
      when /^@Time Duration:/ then
      when /^@Bg:/ then
      when /^@Bg/ then
      when /^@Eg:/ then
      when /^@Eg/ then
      when /^@New Episode/ then
      when /^@Transcriber:/ then
      when /^@Room Layout:/ then
      when /^@Color words:/ then
      when /^@Bck:/ then
      # Added by Jesse
      when /^@PID:/ then
      when /^@Font:/ then  # Not needed, only in Brown/Eve
      else fail "Unknown metadata field: #{field}" end
    end
  end

  def to_a
    a = []
    # Hash of instance variables
    vars = Hash[instance_variables.map { |n| [n, instance_variable_get(n)] }]
    vars.each do |k, v|
      # FIXME: do we just leave symbol keys alone?
      a.push(k => v)
    end
  end
end

def symbols_to_strings(hash)
  # Convert a possibly nested hash's keys to strings if not already.
  # Done here because I'm not sure if extending Hash is bad practice.
  return hash.to_s if !hash.is_a?(Hash) || hash.is_a?(Array)
  hash.each_with_object({}) { |(k, v), h| h[k.to_s] = symbols_to_strings(v) }
end

def get_MOR_token_form(word_group)
  (word_group.map do |w|
    case
    when w[:Type] == :Punctuation then w[:Value]
    when w[:Type] == :PreClitic then w[:Word][:Stem]
    when w[:Type] == :Word then w[:Stem]
    when w[:Type] == :PostClitic then w[:Word][:Stem]
    when w[:Type] == :Compound then (w[:Parts].map { |p| p[:Stem] }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_category(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then w[:Word][:Pos][:Category]
    when w[:Type] == :Word then w[:Pos][:Category]
    when w[:Type] == :PostClitic then w[:Word][:Pos][:Category]
    when w[:Type] == :Compound then
      (w[:Parts].map { |p| p[:Pos][:Category] }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_subcategory(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Word then w[:Pos][:SubCategories].join('|')
    when w[:Type] == :PostClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Compound then
      (w[:Parts].map { |p| p[:Pos][:SubCategories].join('|') }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_subcategory(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Word then w[:Pos][:SubCategories].join('|')
    when w[:Type] == :PostClitic then w[:Word][:Pos][:SubCategories].join('|')
    when w[:Type] == :Compound then
      (w[:Parts].map { |p| p[:Pos][:SubCategories].join('|') }).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_fusionalsuffixes(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then
      w[:Word][:FusionalSuffixes].join('|') if w[:Word][:FusionalSuffixes]
    when w[:Type] == :Word then
      w[:FusionalSuffixes].join('|') if w[:FusionalSuffixes]
    when w[:Type] == :PostClitic then
      w[:Word][:FusionalSuffixes].join('|') if w[:FusionalSuffixes]
    when w[:Type] == :Compound then
      (w[:Parts].map do |p|
        p[:FusionalSuffixes].join('|') if w[:FusionalSuffixes]
      end).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

def get_MOR_token_suffixes(word_group)
  # puts word_group.inspect
  (word_group.map do |w|
    # puts w.inspect
    case
    when w[:Type] == :Punctuation then 'Punct'
    when w[:Type] == :PreClitic then
      w[:Word][:Suffixes].join('|') if w[:Word][:Suffixes]
    when w[:Type] == :Word then
      w[:Suffixes].join('|') if w[:Suffixes]
    when w[:Type] == :PostClitic then
      w[:Word][:Suffixes].join('|') if w[:Word][:Suffixes]
    when w[:Type] == :Compound then
      (w[:Parts].map do |p|
        p[:Suffixes].join('|') if w[:Suffixes]
      end).join('+')
    else fail "Can't handle this form!" end
  end).join('-')
end

# Base CHILDES Utterance class, including instance attributes such
# as the raw utterance, tokenized forms, parsed morphologies, and more.
class CHILDESUtterance
  attr_accessor :num, :raw_utterance, :tokenized, :file_info, :speaker,
                :utterance_tokens, :annotations, :metadata, :corpus_metadata,
                :utterance_xml, :cleaned_utterance, :utterance_tokens, :age,
                :age_bin

  def initialize(num, utterance, filename, metadata)
    # corpusMetadata/@corpus_metadata param/variable omitted.
    # file_info -> filename
    @tokenized = nil
    @num = num
    @filename = filename
    # Make metadata object from Array
    @metadata = CHILDESUtteranceMetadata.new(Array.new(metadata))
    # This is the metadata attached to the corpus file in parent directory

    tokens = utterance.first.split.map(&:strip)

    @speaker = tokens[0].gsub(/[*:]/, '').strip
    # Get everything but first row.
    # We have to make a number of fixes to the raw data to get parsing to work
    @raw_utterance = tokens.slice(1..-1).join(' ').gsub(/[^ ],/, ' ,')

    # Parse chat format
    p = CHAT_PARSER.parse(@raw_utterance)
    if p.nil?
      MISMATCHES.puts "!!!!Can't CHAT Parse: #{@raw_utterance}"
      puts "!!!!Can't CHAT Parse: #{@raw_utterance}"
      $stdout.flush
    else
      @tokenized = p.replace.gsub(
        / ta /, ' to ' # Basic replacements
      ).gsub(
        /mhm/, 'yes'
      ).split.map(&:strip)
    end

    @annotations = Hash.new nil
    annotations = Array.new(utterance.slice(1..-1))
    # TODO: Figure out type of annotations
    annotations.each do |tier|
      case tier
      when /^%mor:/ # Morphemic segments by type and PoS
        # gets rid of tab and %mor
        morph = tier.gsub(/%(.*?):\t/, '').strip

        parse = MOR_PARSER.parse(morph)
        if parse.nil? || parse == []
          MISMATCHES.puts "Can't MOR parse: #{annotations}"
          puts "Can't MOR parse: #{annotations}"
          $stdout.flush
        else
          @annotations[:Morphology] = parse.struct.map(&:first)
          # puts "@annotations[:Morphology]: #{@annotations[:Morphology]}"
          $stdout.flush
        end

        if @tokenized && @annotations[:Morphology]
          # FIXME: Avoid 3+ levels of block nesting
          if @tokenized.length != @annotations[:Morphology].length
            MISMATCHES.puts "Tokenization and morphology don't match:"
            MISMATCHES.puts "\t#{@raw_utterance}"
            MISMATCHES.puts "\t#{@tokenized.join(' ')}"
            MISMATCHES.puts "\t#{morph}"
            # puts "Tokenization and morphology don't match:"
            # puts "\t#{@raw_utterance}"
            # puts "\t#{@tokenized.join(' ')}"
            # puts "\t#{morph}"
            @annotations[:Morphology] = nil
          else
            @tokenized.length.times do |i|
              f = get_MOR_token_form(@annotations[:Morphology][i])
              next if f != @tokenized[i]
              # This happens when stem is different from token
              MISMATCHES.puts "Token and MOR don't match:"
              MISMATCHES.puts "\t#{@tokenized[i]}, #{f}"
              # puts "Token and MOR don't match: #{@tokenized[i]}, #{f}"
            end
          end
        else
          fail "Nil tokenization: #{@raw_utterance}"
          # TODO: We're failing for now, not sure if this should happen at all
          # MISMATCHES.puts "Nil tokenization: #{@raw_utterance}"
          # puts "Nil tokenization: #{@raw_utterance}"
        end
      # Prefacing with x means non-standard CHAT feature
      when /^%xgra:/ # More advanced GRA feature (not sure what though)
        @annotations[:Syntax] = tier.gsub(/%(.*?):\t/, '').split.map(&:strip)
      # FIXME: Can I DRY this?
      # Immediate TODO: Store the symbol into a variable, and convert all to 3
      when /^%com:/ # General comment
        @annotations[:Com] = tier.gsub(/%(.*?):\t/, '')
      when /^%act:/
        @annotations[:Action] = tier.gsub(/%(.*?):\t/, '')
      when /^%int:/
        @annotations[:Intonation] = tier.gsub(/%(.*?):\t/, '')
      when /^%exp:/
        @annotations[:Exp] = tier.gsub(/%(.*?):\t/, '')
      when /^%pho:/
        @annotations[:Phonology] = tier.gsub(/%(.*?):\t/, '')
      when /^%spa:/
        @annotations[:Spa] = tier.gsub(/%(.*?):\t/, '')
      when /^%par:/
        @annotations[:Par] = tier.gsub(/%(.*?):\t/, '')
      when /^%alt:/
        @annotations[:Alt] = tier.gsub(/%(.*?):\t/, '')
      when /^%gpx:/
        @annotations[:Gpx] = tier.gsub(/%(.*?):\t/, '')
      when /^%sit:/
        @annotations[:Sit] = tier.gsub(/%(.*?):\t/, '')
      when /^%add:/
        @annotations[:Add] = tier.gsub(/%(.*?):\t/, '')
      when /^%err:/
        @annotations[:Err] = tier.gsub(/%(.*?):\t/, '')
      when /^%eng:/
        @annotations[:English] = tier.gsub(/%(.*?):\t/, '')
      when /^%trn:/
        @annotations[:Trn] = tier.gsub(/%(.*?):\t/, '')
      when /^%xgrt:/
        @annotations[:Xgrt] = tier.gsub(/%(.*?):\t/, '')
      when /^%pht:/
        @annotations[:Pht] = tier.gsub(/%(.*?):\t/, '')
      # New annotations added
      when /^%gra:/  # Standard grammatical relations tier
        @annotations[:Gra] = tier.gsub(/%(.*?):\t/, '')
      when /%xpho:/  # Non-standard phoneme tier
        @annotations[:Xpho] = tier.gsub(/%(.*?):\t/, '')
      when /^%grt:/  # Standard GRT tier
        @annotations[:grt] = tier.gsub(/%(.*?):\t/, '')
      else fail "Unknown Tier: #{tier}"
      end
    end
  end

  def to_s
    %W(
      Utterance: #{@utterance.inspect}
      File: #{@file.inspect}
      MetaData: #{@metadata.inspect}
      Corpus: #{@corpus.inspect}
    )
  end

  def to_h
    # Convert to a hash for data serialization
    {
      speaker: @speaker,
      raw: @raw_utterance,
      tokenized: @tokenized,
      annotations: @annotations,
      num: @num
    }
  end
end # end childes utterance class

def parseCHILDESFile(filename)
  # Parses a single CHILDES file specified in corpus-file-info.rb
  # corpus_metadata omitted. Not sure what to do about the file_info hash.
  # Maybe an additional optional "metadata" file?

  # Get filename from file_info hash
  puts "Parsing file #{filename}"
  lines = File.readlines(filename)

  # grab the file fields
  fields = []
  last_field = ''
  lines.each do |line|
    case line
    # previously @, \*, and % were all separate fields, but that seems
    # unecessary since the code is the same, so I joined them
    when /^@/, # UTF8, @PID:, @Date, @Media (basically metadata)
         /^\*/, # *CHI, *LOI, TODO find out
         /^%/ # %mor, %gra, %act TODO find out
      fields = fields.push(last_field) unless last_field == ''
      last_field = line
    when /^\t/ then # Some lines are tabbed in, line continuation
      # This just makes sure line continuations are good to go
      last_field += line
    else fail "Don't know how to handle line: #{line}" end
  end

  utt_num = 0
  utterances = []
  metadata = []
  last_utterance = []

  fields.each do |field|
    # Get rid of line break
    field.gsub!(/[\n]/, ' ')
    case field
    when /^@/ then # @PID, @Comment, etc - add to metadata file
      metadata = metadata.push(field) unless field == ''
    when /^\*/ then # These are Utterances *CHI, *PAT, etc
      unless last_utterance == []
        # corpus_metadata param omitted, file_info hash -> filename
        utterances.push(CHILDESUtterance.new(utt_num += 1,
                                             last_utterance,
                                             filename,
                                             metadata))
      end
      # Initialize our last utterance - so * marks beginning of utterances
      last_utterance = [field]
    when /^%/ then # Add to our last_utterance Array
      last_utterance = last_utterance.push(field)
    else fail "Don't know how to handle field: #{field}" end
  end

  utterances
end

def count_words(utterance)
  # puts utterance
  fail 'Utterance has not been tokenized' unless utterance.tokenized
  fail 'No morphology' unless utterance.annotations[:Morphology]
  fail 'Invalid speaker role' if
    /(Target_Child|Child|Playmate|Non_Human|Environment|Camera_Operator)/ =~
    utterance.metadata.participants[utterance.speaker][:Role]
  fail 'Age outside range' unless 18.0 <= utterance.age && utterance.age <= 60.0

  # For every token...
  utterance.tokenized.length.times do |index|
    word = utterance.tokenized[index]
    # Get the morphology of the word
    morphology = utterance.annotations[:Morphology][index]
    # Get morphology token of the word
    mor_cat = get_MOR_token_category(morphology)
    next unless /^(v|aux|part)$/ =~ mor_cat
    # If a verb, aux, or participle
    # Get fusional suffix from .tt grammar parse
    fusional = get_MOR_token_fusionalsuffixes(morphology)
    # same as above
    suffix = get_MOR_token_suffixes(morphology)
    # mor_subcat = get_MOR_token_subcategory(morphology)
    # puts "[fusional, suffix]"
    # puts [fusional, suffix]
    # puts "mor_cat"
    # puts mor_cat
    tag = case mor_cat
          # FIXME: This v does not always mean verb, as evidenced
          # by the very large amount of "Cannot find an entry for...
          # With words like bed, interesting, box, page, etc
          when /^v$/ then
            case [fusional, suffix]
            when ['', 'PAST'] then 'VBD' # regulars
            when ['PAST', ''] then 'VBD' # irregulars
            when ['PRES', ''] then 'VBP' # are
            when ['PAST', ''] then 'VBD' # was
            when ['PAST|13S', ''] then 'VBD' # was
            when ['', '3S'] then 'VBZ'
            when ['3S', ''] then 'VBZ'
            when ['ZERO', ''] then 'VBP' # weak verbs
            when ['1S', ''] then 'VBP' # am
            when ['', ''] then (word == 'be') ? 'VB' : 'VBP'
            else
              $stderr.puts %W(
                Don't know verb type: #{suffix} for word '#{word}'
                with suffix '#{suffix}' and fusional '#{fusional}'
              )
            end
          when /^aux$/ then
            case [fusional, suffix]
            # when ["", "PAST"] then "VBD"
            when ['PAST', ''] then 'VBD' # did
            when ['PRES', ''] then 'VBP' # are
            when ['COND', ''] then 'VBP' # would
            when ['', ''] then # shall, can, etc.
              if word == 'could' then 'VBD'
              elsif word == 'be' then 'VB'
              else 'VBP'
              end
            when ['3S', ''] then 'VBZ'
            when ['PAST|13S', '']  then 'VBD' # was
            when ['PERF', '']  then 'VBN' # been
            # Updated by Jesse
            when ['PASTP', ''] then 'VBN' # Updated been
            when ['', 'PRESP'] then 'VBG' # -ing
            when ['1S', ''] then 'VBP' # am
            else $stderr.puts %W(
              Don't know auxiliary type: #{suffix} for word '#{word}'
              with suffix '#{suffix}' and fusional '#{fusional}'
            )
            end
          when /^part$/ then
            case [fusional, suffix]
            when ['', 'PERF'] then 'VBN'
            when ['', 'PROG'] then 'VBG'
            when ['PERF', ''] then 'VBN'
            # ING verbs seems to be Gerund
            # Updated by Jesse
            when ['', 'PRESP'] then 'VBG' # -ing
            when ['PASTP', ''] then 'VBN' # -en
            when ['', 'PASTP'] then 'VBN' # -en
            else
              $stderr.puts %W(
                Don't know participle type: #{suffix} for word '#{word}'
                with category '#{mor_cat}' and fusional '#{fusional}'
              )
            end
          else fail "Don't know this verbal category!!" end

    if VERB_DATA.include?([word, tag])
      # puts "#{word},#{mor_cat},#{mor_subcat},#{fusional},#{suffix}"
      # Add one utterance count
      AGES[utterance.age_bin][[word, tag]] += 1
    else
      $stderr.puts "Cannot find an entry for: (#{word}, #{tag})"
      $stderr.puts "\t'#{utterance.tokenized.join(' ')}'"
      $stderr.puts "\tfrom file: '#{utterance.filename}'"
      $stderr.puts "\tmor_cat: '#{mor_cat}', fusional: '#{fusional}'"
      $stderr.puts "\tsuffix: '#{suffix}'"
      puts morphology
    end
  end
end

def transcribe(utterances, filename)
  # Set up metadata
  trans = {
    metadata: utterances[0].metadata.to_a,
    utterances: utterances.collect(&:to_h)
  }
  puts YAML.dump(trans)
end

def words_to_YAML(utterances, filename)
  result = Hash.new do |hash, key|
    hash[key] = Hash.new nil
  end

  AGES.each_key do |age|
    AGES[age].each_pair do |verb, count|
      data = VERB_DATA[verb]
      result[age][verb] = {
        CHILDESCount: count.to_i,
        Age: age.to_i,
        Form: data[:Form].to_s,
        Category: data[:Category].to_s,
        Lemma: data[:Lemma].to_s,
        StemTransform: data[:StemTransform].to_s,
        Suffix: data[:Suffix].to_s,
        CELEXFrequency: data[:CELEXFrequency].to_i,
        PTBFrequency: data[:PTBFrequency].to_i
      }
    end
  end

  DataReader.save(filename, result, :YAML, true)
end

corpus_metadata = {}
# For each file specified in corpus-file-info.rb
CorpusInfo::CHILDES_FILES.each do |file_info|
  # File_info is an array of hashes, each specifying one .cha file
  # We parse each file individually

  # Bloom70:Peter
  # Top becomes Bloom70
  top, _ = file_info[:Corpus].split(':')
  # There needs to be a metadata file.
  # Top is corpus folder, CHILDES_DIRECTORY specified up top
  metadata_file = "#{CHILDES_DIRECTORY}/#{top}/0metadata.cdc"

  # If the metadata, and thus corpus, hasn't been processed yet
  unless corpus_metadata.key?(metadata_file)
    # Only prints if it's the first file in the corpus being parsed
    $stderr.puts "Processing Corpus: #{file_info[:Corpus]}"
    # Read the contents of the metadata file as a value for the
    # corpus_metadata hash, where the file name is key
    corpus_metadata[metadata_file] = File.new(metadata_file, 'r').readlines
  end

  utterances = parseCHILDESFile(file_info, corpus_metadata[metadata_file])

  # This is dependent on the behavior we want
  # words_to_YAML(utterances, './CHILDES-by-ages.yaml')
  transcribe(utterances, './CHILDES-by-ages.yaml')
end
