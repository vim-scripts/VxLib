" vim:set fileencoding=utf-8 sw=3 ts=3 et:vim
"
" Author: Marko Mahnič
" Created: October 2009
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.

if exists('s:vxlib_plugin_loaded')
   finish
endif
let s:vxlib_plugin_loaded = 1

" Use in a script that needs SID/SNR.
" Example: 
"     exec vxlib#plugin#MakeSID()
"     exec 'nmap <F8> :call ' . s:SNR . 'DoIt()<cr>'
function! vxlib#plugin#MakeSID()
   let sid_script = "map <SID>xx <SID>xx\n" .
      \ "let s:SID = substitute(maparg('<SID>xx'), '<SNR>\\(\\d\\+_\\)xx$', '\\1', '') \n" .
      \ "unmap <SID>xx\n" .
      \ "let s:SNR = '<SNR>' . s:SID"
   return sid_script
endfunc

" Check if the variable 'name' exists. Create it with the value 'default' if
" it doesn't.
" @param name - string, the name of the global variable ("g:...")
" @param default - string, a vim expression that will give the initial value
" @returns - nothing
function! vxlib#plugin#CheckSetting(name, default)
   if !exists(a:name)
      exec 'let ' . a:name . '=' . a:default
   endif
endfunc

" @var g:VxPlugins - plugins enabeld/disabled by the user in .vimrc (using VxLet).
" The variable is used by IsEnabled, which also checks for variables named
" g:vxenabled_<plugin-name>.
call vxlib#plugin#CheckSetting('g:VxPlugins', '{}')

" @var g:VxPluginEnabledDefault - default value to use when a plugin is not
" explicitly enabled/disabled.
call vxlib#plugin#CheckSetting('g:VxPluginEnabledDefault', '1')

" @var g:VxPluginLoaded - describes the load-state of a plugin; @see
" GetLoadStatus().
call vxlib#plugin#CheckSetting('g:VxPluginLoaded', '{}')

" @var g:VxPluginMissFeatures - the missing Vim features that prevent this
" plugin to be loaded.
call vxlib#plugin#CheckSetting('g:VxPluginMissFeatures', '{}')

" @var g: VxPluginErrors - the erors encountered in the .vim/plugin section of
" for plugins that didn't load correctly.
call vxlib#plugin#CheckSetting('g:VxPluginErrors', '{}')

" @var g:VxKnownPlugins - when PluginExists searches for a plugin it stores
" the result in this dictionary for later use.
call vxlib#plugin#CheckSetting('g:VxKnownPlugins', '{}')

" @var g:VxPluginVar - plugins may store global (state) variables in this
" dictionary.
call vxlib#plugin#CheckSetting('g:VxPluginVar', '{}')

" Something to autoload this module from .vimrc
function! vxlib#plugin#Init()
endfunc

" Check if the plugin 'idPlugin' is enabled
function! vxlib#plugin#IsEnabled(idPlugin)
   let enbl = get(g:VxPlugins, a:idPlugin, -9875) 
   if enbl == -9875
      let name = 'g:vxenabled_' . a:idPlugin
      if exists(name)
         exec "let enbl=(" . name . "!=0)"
         let g:VxPlugins[a:idPlugin] = enbl
      else
         let enbl = g:VxPluginEnabledDefault
      endif
   endif
   return enbl
endfunc

function! vxlib#plugin#SetEnabled(idPlugin, value)
   let g:VxPlugins[a:idPlugin] = a:value
endfunc

function! vxlib#plugin#Enable(idPlugin)
   let g:VxPlugins[a:idPlugin] = 1
endfunc

function! vxlib#plugin#Disable(idPlugin)
   let g:VxPlugins[a:idPlugin] = 0
endfunc

" @returns the plugin-loaded status for the plugin 'idPlugin'.
" Status:
"    1 - loaded
"    0 - not loaded, probably unknown
"    negative: could not (completely) load
"    -1 - disabled
"    -2 - missing vim features
"    -3 - TODO: missing plugins. The script is given this status on pass 1 when
"         one of the required plugins is missing. The file with the plugin is
"         added to the queue of files to be reloaded. On pass 2 only the
"         plugins with this status are processed (StopLoading shoud return 0).
"         If the plugin is successfully loaded on pass 2, its status is set to
"         1, otherwise the list of missing plugins is created for the plugin.
"    -9 - errors in plugin code
function! vxlib#plugin#GetLoadStatus(idPlugin)
   return get(g:VxPluginLoaded, a:idPlugin, 0)
endfunc

" Return true if the plugin was loaded without problems.
function! vxlib#plugin#IsLoaded(idPlugin)
   return get(g:VxPluginLoaded, a:idPlugin, 0) > 0
endfunc

" Set the plugin's loaded state.
function! vxlib#plugin#SetLoaded(idPlugin, markLoaded)
   let g:VxPluginLoaded[a:idPlugin] = a:markLoaded
endfunc

" Check if the plugin 'idPlugin' is loaded.
" If the plugin isn't marked as loaded, it will be marked as such.
function! s:CheckAndSetLoaded(idPlugin, value)
   let loaded = get(g:VxPluginLoaded, a:idPlugin, 0)
   if ! loaded
      let g:VxPluginLoaded[a:idPlugin] = a:value
   endif
   return loaded
endfunc

" Check if the plugin 'idPlugin' is loaded.
" If the plugin isn't marked as loaded, it will be marked as such.
"
" Used as a script loading guard: if StopLoading(id) | finish | endif
"
function! vxlib#plugin#StopLoading(idPlugin)
   return s:CheckAndSetLoaded(a:idPlugin, 1)
endfunc

" List all known plugins
function! vxlib#plugin#List()
   let loaded = []
   let disabled = []
   let missing = []
   let errors = []
   let allmet = keys(g:VxPluginLoaded)
   call sort(allmet)
   for k in allmet
      let state = g:VxPluginLoaded[k]
      if state > 0 | call add(loaded, k)
      else
         if state == -1 | call add(disabled, k)
         elseif state == -2 | call add(missing, k)
         else | call add(errors, k)
         endif
      endif
   endfor
   if len(loaded) > 0 | echo 'Loaded plugins:'
      for k in loaded
         echo '   ' . g:VxPluginLoaded[k] . ' ' . k
      endfor
   endif
   if len(disabled) > 0 | echo 'Disabled plugins:'
      for k in disabled
         echo '   ' . g:VxPluginLoaded[k] . ' ' . k
      endfor
   endif
   if len(missing) > 0 | echo 'Reuqired features not available:'
      for k in missing
         echo '   ' . g:VxPluginLoaded[k] . ' ' . k . "\t" . get(g:VxPluginMissFeatures, k, '?')
      endfor
   endif
   if len(errors) > 0 | echo 'Plugins failed to load:'
      for k in errors
         echo '   ' . g:VxPluginLoaded[k] . ' ' . k . "\t" . get(g:VxPluginErrors, k, '?')
      endfor
   endif
   let enabled = keys(g:VxPlugins)
   call sort(enabled)
   if len(enabled) > 0 | echo 'Plugins explicitly enabled/disabled:'
      for k in enabled
         echo '   ' . g:VxPlugins[k] . ' ' . k
      endfor
   endif
   let errors = keys(g:VxPluginErrors)
   call sort(errors)
   if len(errors) > 0 | echo 'Reported errors:'
      for k in errors
         echo '   ' . g:VxPluginErrors[k] . ' ' . k
      endfor
   endif

   " Doesn't work with VxCmd: double call to #Capture! --> redir TODO: recursive capture
   "let loaded = vxlib#cmd#Capture(":let", 1)
   "call filter(loaded, 'v:val =~ "^loaded_"')
   "if len(loaded) > 0 | echo 'Other plugins:'
   "   call map(loaded, 'matchstr(v:val, "^loaded_\\zs.*$")')
   "   for line in loaded
   "      echo '   ' . line
   "   endfor
   "endif
endfunc

function! s:VxLet(dict, key, ...)
   if ! exists('g:' . a:dict)
      exec 'let g:' . a:dict . '={}'
   endif
   let value = join(a:000, ' ')
   if value != "" 
      exec 'let g:' . a:dict . "['" . a:key . "']=" . value
   endif
endfunc
command -nargs=+ VxLet call s:VxLet(<f-args>)
" TODO: VxLet - add completion with function (for 0=global dictionaries, 1=keys)

function! s:VxStatus()
   if vxlib#plugin#IsLoaded("vimuiex_vxcapture")
      VxCmd call vxlib#plugin#List()
   else
      call vxlib#plugin#List()
   endif
endfunc
command VxStatus call s:VxStatus()

" Special case: can't use #StopLoading before it is created.
call vxlib#plugin#SetLoaded('#au#vxlib#plugin', 1)


function! vxlib#plugin#PluginExists(name, plugfile)
   try
      let knp = g:VxKnownPlugins[a:name]
      return knp != 0
   catch /.*/
   endtry
   if exists('g:loaded_' . a:name)
      exec 'let g:VxKnownPlugins[a:name]=g:loaded_'. a:name
      return 1
   endif
   if a:plugfile =~ '^\w\+/\w'
      let plugfiles=globpath(&rtp, a:plugfile)
      if len(plugfiles) > 0
         let g:VxKnownPlugins[a:name] = plugfiles
         return 1
      endif
   endif
   let g:VxKnownPlugins[a:name] = 0
   return 0
endfunc

" =========================================================================== 
" Global Initialization - Processed by Plugin Code Generator
" =========================================================================== 
finish

" Checks for the existence of normal plugins
" Note: atm it doesn't work (well) with plugin-generator-generated plugins
" <PLUGINFUNCTION id="vxlib#pluginexists" name="PluginExists">
function! s:PluginExists(name, plugfile)
   return vxlib#plugin#PluginExists(a:name, a:plugfile)
endfunc
" </PLUGINFUNCTION>
