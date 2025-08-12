param(
  [Parameter(Mandatory=$true)]
  [string]$InputCsv,

  # Topic prefix used in your predicate pattern (e.g., 'aa.ff')
  [string]$TopicPrefix = 'aa.ff',

  # If your topic includes schema (aa.ff.<schema>.<table>), set this switch
  [switch]$IncludeSchemaInPattern,

  # SMT / predicate types you showed
  [string]$TransformType = 'kfk',
  [string]$PredicateType = 'x'
)

function Escape-ForRegex([string]$s) {
  # Escape dots and other regex metachars
  return [regex]::Escape($s)
}

function Safe-Name([string]$s) {
  # Alphanumerics and underscore; lowercased
  return ($s -replace '[^\w]', '_').ToLower()
}

if (!(Test-Path $InputCsv)) {
  throw "Input CSV not found: $InputCsv"
}

$rows = Import-Csv -Path $InputCsv
if (-not $rows -or -not ($rows | Get-Member -Name schema_name -MemberType NoteProperty)) {
  throw "CSV must have headers: schema_name,table_name,column_name"
}

# Group by schema + table
$groups = $rows | Group-Object { "$($_.schema_name)|$($_.table_name)" }

# Start YAML
$yaml = New-Object System.Collections.Generic.List[string]

# --- Transforms (one per table)
foreach ($g in $groups) {
  $first = $g.Group[0]
  $schema = $first.schema_name
  $table  = $first.table_name

  $predicateName = "pred_{0}_{1}" -f (Safe-Name $schema), (Safe-Name $table)

  # Build after./before. cast list
  $cols = $g.Group | Select-Object -ExpandProperty column_name
  # Ensure distinct & stable
  $cols = $cols | Sort-Object -Unique
  $casts = @()
  foreach ($col in $cols) {
    $casts += "after.$col:string"
    $casts += "before.$col:string"
  }
  $configLine = ($casts -join ',')

  # Transform block
  $yaml.Add("- type: $TransformType")
  $yaml.Add("  predicate: $predicateName")
  $yaml.Add("  config: $configLine")
  $yaml.Add("") # blank line
}

# --- Predicates mapping
$yaml.Add("predicates:")
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

# Output YAML
$yaml -join "`n"
