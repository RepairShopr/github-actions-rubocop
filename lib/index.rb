# frozen_string_literal: true

require 'net/http'
require 'json'
require 'time'

@GITHUB_SHA = ENV['GITHUB_SHA']
@GITHUB_EVENT_PATH = ENV['GITHUB_EVENT_PATH']
@GITHUB_TOKEN = ENV['GITHUB_TOKEN']
@GITHUB_WORKSPACE = ENV['GITHUB_WORKSPACE']

@event = JSON.parse(File.read(ENV['GITHUB_EVENT_PATH']))
@repository = @event['repository']
@owner = @repository['owner']['login']
@repo = @repository['name']

@check_name = 'Rubocop'

@headers = {
  "Content-Type": 'application/json',
  "Accept": 'application/vnd.github.antiope-preview+json',
  "Authorization": "Bearer #{@GITHUB_TOKEN}",
  "User-Agent": 'github-actions-rubocop'
}

class GithubAPIError < StandardError; end

def create_check
  body = {
    'name' => @check_name,
    'head_sha' => @GITHUB_SHA,
    'status' => 'in_progress',
    'started_at' => Time.now.iso8601
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs"

  resp = http.post(path, body.to_json, @headers)

  if resp.code.to_i >= 300
    puts "[Github Create Check] Failed Posting to Github: #{resp.message}" 
    raise GithubAPIError.new(resp.message )
  end

  data = JSON.parse(resp.body)
  data['id']
end

def update_check(id, conclusion, output)
  puts "[#{id}] Updating check #{conclusion}"
  body = {
    'name' => @check_name,
    'head_sha' => @GITHUB_SHA,
    'status' => 'completed',
    'completed_at' => Time.now.iso8601,
    'conclusion' => conclusion,
    'output' => output
  }

  http = Net::HTTP.new('api.github.com', 443)
  http.use_ssl = true
  path = "/repos/#{@owner}/#{@repo}/check-runs/#{id}"

  resp = http.patch(path, body.to_json, @headers)

  if resp.code.to_i >= 300
    puts "[Github Update Check] Failed Posting to Github: #{resp.message}" 
    raise GithubAPIError.new(resp.message)
  end
end

@annotation_levels = {
  'refactor' => 'failure',
  'convention' => 'failure',
  'warning' => 'warning',
  'error' => 'failure',
  'fatal' => 'failure'
}

def run_rubocop
  annotations = []
  errors = nil
  conclusion = 'success'
  count = 0

  # changed files of commit
  current_commit,previous_commit = `git log -n 2 --format=format:%H`.split("\n")
  changed_files = `git diff --name-only #{current_commit}..#{previous_commit}`.split("\n")
  puts "Modified files of this commit: \n#{changed_files.join("\n")}\n"
  changed_files.delete_if{ |filename| filename[-3..-1] != '.rb' }

  changed_files = ["app/models/new_account_lead.rb", "config/routes.rb", "spec/requests/new_account_leads_spec.rb"]
  if changed_files.length > 0
    puts "Running rubocop on these files: #{changed_files}"
    Dir.chdir(@GITHUB_WORKSPACE) do
      # only run rubocop on changes files
      output = `rubocop --format json #{changed_files}`
      puts output.inspect
      errors = JSON.parse(output_text)
    end

    errors['files'].each do |file|
      path = file['path']
      offenses = file['offenses']

      offenses.each do |offense|
        severity = offense['severity']
        message = offense['message']
        location = offense['location']
        annotation_level = @annotation_levels[severity]
        count += 1

        conclusion = 'failure' if annotation_level == 'failure'

        annotations.push(
          'path' => path,
          'start_line' => location['start_line'],
          'end_line' => location['start_line'],
          "annotation_level": annotation_level,
          'message' => message
        )
      end
    end
  else
    puts "No new ruby files to run rubocop on, exiting..."
  end

  output = {
    "title": @check_name,
    "summary": "#{count} offense(s) found",
    'annotations' => annotations
  }

  { 'output' => output, 'conclusion' => conclusion }
end

def run
  puts "\nStarting Rubocop..."

  id = create_check
  results = run_rubocop
  conclusion = results['conclusion']
  output = results['output']

  puts "Results:\n\n#{output.inspect}"

  update_check(id, conclusion, output)
  update_check(id, 'failure', nil) if conclusion == 'failure'
end

run
