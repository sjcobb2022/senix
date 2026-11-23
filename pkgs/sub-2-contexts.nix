{ runCommand }:
{
  context,
  subs,
}:
runCommand "sub-2-contexts" { } ''
  mkdir $out
  # Do a symlink so we do not have multiple copies of the potentially large file_contexts file
  ln -s ${context} $out/file_contexts
  [ -e ${context}.subs_dist ] && ln -s ${context}.subs_dist $out/file_contexts.subs_dist
  cp ${subs} $out/file_contexts.subs
''
