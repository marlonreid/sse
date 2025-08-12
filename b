param(
  [Parameter(Mandatory=$true)]
  [string]$InputCsv,

  # Topic prefix used in your predicate pattern (e.g., 'aa.ff')
  [string]$TopicPrefix = 'aa.ff',

  # If your topic is aa.ff.<schema>.<table>, set this switch
  [switch]$IncludeSchemaInPattern,

  # Your SMT / predicate types
  [string]$TransformType = 'kfk',
  [string]$PredicateType = 'x'
)

function Escape-ForRegex([string]$s) { [regex]::Escape($s) }
function Safe-Name([string]$s) { ($s -replace '[^\w]', '_').ToLower() }

if (!(Test-Path $InputCsv)) { throw "Input CSV not found: $InputCsv" }

$rows = Import-Csv -Path $InputCsv
foreach ($req in 'schema_name','table_name','column_name') {
  if (-not ($rows | Get-Member -Name $req -MemberType NoteProperty)) {
    throw "CSV must have headers: schema_name, table_name, column_name"
  }
}

# Sort for stable output
$rows = $rows | Sort-Object schema_name, table_name, column_name

$yaml = New-Object System.Collections.Generic.List[string]

# ----- Transform blocks (ONE PER COLUMN)
foreach ($r in $rows) {
  $schema = $r.schema_name
  $table  = $r.table_name
  $col    = $r.column_name

  $predicateName = "pred_{0}_{1}" -f (Safe-Name $schema), (Safe-Name $table)

  $yaml.Add("- type: $TransformType")
  $yaml.Add("  predicate: $predicateName")
  $yaml.Add("  config: after.$col:string,before.$col:string")
  $yaml.Add("") # blank line
}

# ----- Predicates (ONE PER TABLE)
$yaml.Add("predicates:")
$groups = $rows | Group-Object { "$($_.schema_name)|$($_.table_name)" }
foreach ($g in $groups) {
  $first = $g.Group[0]
  $schema = $first.schema_name
  $table  = $first.table_name

  $predicateName = "pred_{0}_{1}" -f (Safe-Name $schema), (Safe-Name $table)

  $prefixEsc = ($TopicPrefix -replace '\.', '\\.')
  $schemaEsc = Escape-ForRegex $schema
  $tableEsc  = Escape-ForRegex $table

  if ($IncludeSchemaInPattern.IsPresent) {
    $pattern = "{0}\.{1}\.{2}" -f $prefixEsc, $schemaEsc, $tableEsc
  } else {
    $pattern = "{0}\.{1}" -f $prefixEsc, $tableEsc
  }

  $yaml.Add("  $predicateName:")
  $yaml.Add("    type: $PredicateType")
  $yaml.Add("    config:")
  $yaml.Add("      pattern: $pattern")
}

$yaml -join "`n"
