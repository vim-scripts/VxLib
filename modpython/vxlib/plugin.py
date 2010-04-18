#!/usr/bin/env python
# vim:set fileencoding=utf-8 sw=4 ts=8 et:vim
#
# Author:  Marko Mahnič
# Created: October 2009 
# License: GPL (http://www.gnu.org/copyleft/gpl.html)
# This program comes with ABSOLUTELY NO WARRANTY.

import os, sys, stat
import shutil
import optparse
import re, string
import datetime
import plugconf

options = None
config = None

separator = '''\n" ================================\n'''
file_head = '''\
" This file is autogenerated. DO NOT EDIT. Changes will be lost.
" Generator: vxlib/plugin.py
"if vxlib#plugin#StopLoading('_plugin_autogen_${timestamp}')
"   finish
"endif

${usergen_check_finish}\

let s:exception_list = []

function! s:StrHas(ftrlist)
   let ftrs=split(a:ftrlist, ',')
   let hftrs=[]
   for f in ftrs
       call add(hftrs, (has(f) ? '+' : '-') . f)
   endfo
   return join(hftrs, ' ')
endfunc\
'''

usergen_finish_block='''
if !exists("g:vxlib_user_generated_plugins") || !g:vxlib_user_generated_plugins
   finish
endif
'''

plugin_proxies='''
function! s:Exception(throwpoint, exception, plugid, loadstatus)
   if a:loadstatus != 0
      call vxlib#plugin#SetLoaded(a:plugid, a:loadstatus)
   endif
   call add(s:exception_list, matchstr(a:throwpoint, ',\s*\zsline\s\+\d\+') . ' (' . a:plugid . '):')
   call add(s:exception_list, '   ' . a:exception)
   let g:VxPluginErrors[a:plugid] = a:exception
endfunc

function! s:CheckSetting(name, default)
   if !exists(a:name)
      exec 'let ' . a:name . '=' . a:default
   endif
endfunc

function! s:IsEnabled(name)
   return vxlib#plugin#IsEnabled(a:name)
endfunc

function! s:GetLoadStatus(name)
   return vxlib#plugin#GetLoadStatus(a:name)
endfunc

function! s:SetLoaded(name, value)
   return vxlib#plugin#SetLoaded(a:name, a:value)
endfunc

function! s:SetEnabledDefault(name, value)
   if ! has_key(g:VxPlugins, a:name) && ! exists("g:vxenabled_" . a:name)
       call vxlib#plugin#SetEnabled(a:name, a:value)
   endif
endfunc

function! s:ContinueLoading(name)
   if ! vxlib#plugin#IsEnabled(a:name)
      call vxlib#plugin#SetLoaded(a:name, -1)
   elseif ! vxlib#plugin#GetLoadStatus(a:name)
      return 1
   endif
   return 0
endfunc
'''
plugin_proxies_standalone='''
function! s:Exception(throwpoint, exception, plugid, loadstatus)
   if a:loadstatus != 0
      call s:SetLoaded(a:plugid, a:loadstatus)
   endif
   call add(s:exception_list, matchstr(a:throwpoint, ',\s*\zsline\s\+\d\+') . ' (' . a:plugid . '):')
   call add(s:exception_list, '   ' . a:exception)
endfunc

function! s:CheckSetting(name, default)
   if !exists(a:name)
      exec 'let ' . a:name . '=' . a:default
   endif
endfunc

function! s:IsEnabled(name)
   if !exists('g:loaded_' . a:name) | return 1 | endif
   exec 'let ldval=g:loaded_' . a:name
   return ldval >= 0
endfunc

function! s:GetLoadStatus(name)
   if !exists('g:loaded_' . a:name) | return 0 | endif
   exec 'let ldval=g:loaded_' . a:name
   return ldval > 0
endfunc

function! s:SetLoaded(name, value)
   exec 'let g:loaded_' . a:name . '=' . a:value
endfunc

function! s:SetEnabledDefault(name, value)
   if s:GetLoadStatus(a:name) != 0 | return | endif
   if a:value | call s:SetLoaded(a:name, 0)
   else | call s:SetLoaded(a:name, 1)
   endif
endfunc

function! s:ContinueLoading(name)
   if ! s:IsEnabled(a:name) | call s:SetLoaded(a:name, -1)
   elseif ! s:GetLoadStatus(a:name) | return 1
   endif
   return 0
endfunc
'''
file_tail ='''\
for err in s:exception_list
   echoerr err
endfor
let s:exception_list = []
'''

# Calling echoerr from autocmd locks (g)vim.
this_tail_not_working = '''
function! s:NotifyErrors()
   autocmd! G_Notify_Errors_onetime
   echoerr 'This is a test'
endfunc
augroup G_Notify_Errors_onetime
  autocmd!
  autocmd BufWinEnter,VimEnter *
     \ call s:NotifyErrors() | delfunc s:NotifyErrors
augroup END
'''

class CPluginWriter_A:
    def __init__(self):
        self.plugin_code_block = """\
        " Source: ${filename}
        " START Plugin
        let s:curplugin='${pluginid}'
        ${set_enabled}\
        if s:ContinueLoading(s:curplugin)
        ${if_require}\
          try\
        ${plugin_code}
        ${startup_blok}
            call ${vxlib_plugin}SetLoaded(s:curplugin, 1)
          catch /.*/
            call s:Exception(v:throwpoint, v:exception, s:curplugin, -9)
          endtry
        ${endif_require}\
        endif
        " END Plugin
        """

        self.startup_code_block = """\
           " STARTUP
           function! s:G_${plugin}_auto_startup()
            try
              autocmd! G_${plugin}_auto_onetime\
        ${startup_code}
            catch /.*/
              call s:Exception(v:throwpoint, v:exception, 'Startup: ${pluginid}', 0)
            endtry
           endfunc
           augroup G_${plugin}_auto_onetime
              autocmd!
              autocmd BufWinEnter,VimEnter *
                 \ call s:G_${plugin}_auto_startup()
                 \ | delfunc s:G_${plugin}_auto_startup
           augroup END
           " END-STARTUP\
        """

        self.if_require_str = """\
         if !(${require_vim_expr})
           call ${vxlib_plugin}SetLoaded(s:curplugin, -2)
           let g:VxPluginMissFeatures[s:curplugin] = '${require_expr}: ' ${require_status}
         else
        """

        self.endif_require_str = """\
         endif
        """

        # Added when option 'enabled=' is uncommented in the config file.
        # Note: This increases the loading time for 10-20% (tested 12 plugins; all off vs. all on)
        # Reason: dictionary lookup + set value
        self.set_enabled_str = """\
         call s:SetEnabledDefault(s:curplugin, %d)
        """
        self.set_enabled_str = """\
        if ! has_key(g:VxPlugins, s:curplugin) | call vxlib#plugin#SetEnabled(s:curplugin, %d) | endif
        """


    def writeFileHead(self, out):
        global options
        now = datetime.datetime.utcnow()
        dt = "%06x:%04x" % (now.toordinal(), now.hour * 3600 + now.minute * 60 + now.second)

        tvars = {"timestamp": dt, "usergen_check_finish": ""}
        if options.usergenerated: tvars["usergen_check_finish"] = usergen_finish_block
        out.write(string.Template(file_head).substitute(tvars))
        #if options.standalone: out.write(plugin_proxies_standalone)
        #else: out.write(plugin_proxies)
        out.write(plugin_proxies)

    def writePluginFunctions(self, plugfuncs, out):
        for f in plugfuncs:
            if not f.isUsed(): continue
            if not f.hasCode(): continue
            out.write("\n" + f.getCode() + "\n")

    def writeFileTail(self, out):
        out.write(separator)
        out.write(file_tail)

    def writePluginCode(self, plugins, out):
        # how to call vxlib#plugin functions (with local proxy or directly)
        #   vxlib_plugin = "s:"
        #   vxlib_plugin = "vxlib#plugin#"
        for p in plugins:
            if p.isGenerated < 1: continue
            tvars = p.getTemplateVars()
            tvars["vxlib_plugin"] = "s:"
            
            # Explicitly enabled/disabled plugin
            enbl = p.getEnabled()
            if enbl == None: tvars["set_enabled"] = ""
            else:
                tvars["set_enabled"] = self.set_enabled_str % (1 if enbl else 0)

            # prepare 'require' blocks
            if tvars["require_vim_expr"] == "":
                tvars["if_require"] = ""
                tvars["endif_require"] = ""
            else:
                tvars["if_require"] = string.Template(self.if_require_str).substitute(tvars)
                tvars["endif_require"] = self.endif_require_str

            # prepare 'startup' blocks
            if len(p.codeStartup) < 1:
                tvars["startup_blok"] = ""
            else:
                tvars["startup_blok"] = string.Template(self.startup_code_block).substitute(tvars)

            # finally create the 'code' block
            codeblock = string.Template(self.plugin_code_block).substitute(tvars)
            out.write(separator)
            out.write(codeblock)

        return


def buildRequire(expr):
    global options
    if not options.add_require:
        return ("", "")
    expr = expr.replace('"', '').replace("'", "")
    haspat = """has('%s')"""
    ifexpr = ""; hasexpr = ""; prev = 0
    features = {}
    for mo in re.finditer(r'''[()!]|(\&\&)|(\|\|)''', expr):
        text = expr[prev:mo.start()].strip()
        if text != "":
            ifexpr += haspat % text
            features[text] = 1
        ifexpr += mo.group(0)
        prev = mo.end()
    text = expr[prev:].strip()
    if text != "":
        ifexpr += haspat % text
        features[text] = 1
    hasexpr = '''. s:StrHas('%s')''' % (",".join(sorted(features.keys())))

    if ifexpr == "": return ("", "")
    return (ifexpr, hasexpr)


class CPlugin:
    def __init__(self):
        self.filename = ""
        self.pluginId = ""
        self.featureExpr = ""
        self.dependsExpr = ""
        self.config = None
        self.codePlugin = []
        self.codeStartup = []
        self.errors = []

    @property
    def varName(self):
        return re.sub("[^a-zA-Z0-9_]+", "_", self.pluginId)

    @property
    def shortFilename(self):
        p = os.path
        return p.join(p.basename(p.dirname(self.filename)), p.basename(self.filename))

    @property
    def isGenerated(self):
        try: generate = int(self.config.getValue("generate"))
        except: generate = 1
        return generate

    def getEnabled(self):
        enbl = self.config.getValue("enabled")
        if enbl == None: return None
        try: enbl = int(enbl)
        except: enbl = 1
        return enbl

    def getTemplateVars(self):
        tvars = {}
        tvars["pluginid"] = self.varName.strip("_") # self.pluginId
        tvars["plugin"] = self.varName
        tvars["filename"] = self.shortFilename

        # Code
        if len(self.codePlugin) < 1: tvars["plugin_code"] = ""
        else: tvars["plugin_code"] = "\n" + "\n".join(self.codePlugin)
        if len(self.codeStartup) < 1: tvars["startup_code"] = ""
        else: tvars["startup_code"] = "\n" + "\n".join(self.codeStartup)

        # Required features
        ifreq, has_status = buildRequire(self.featureExpr)
        if ifreq == "":
            tvars["require_vim_expr"] = ""
            tvars["require_expr"] = ""
            tvars["require_status"] = ""
        else:
            tvars["require_vim_expr"] = ifreq
            tvars["require_expr"] = self.featureExpr
            tvars["require_status"] = has_status
        return tvars

class CPlugFunction:
    def __init__(self):
        self.filename = ""
        self.funcId = ""
        self.funcName = "" # used for calculation of usecount
        self.code = []
        self.errors = []
        self.usecount = 0
        pass

    def hasCode(self):
        return self.code != None and len(self.code) > 0

    def getCode(self):
        if not self.hasCode(): return ""
        else: return "\n".join(self.code)

    def isUsed(self):
        return self.usecount > 0

    def resetUseCount(self):
        if len(self.funcName) < 1: self.usecount = 1
        elif not self.hasCode(): self.usecount = 1
        else: self.usecount = 0
        if self.usecount != 0: return

        # verify if the function is really defined
        for line in self.code:
            if line.find(self.funcName) > 0: return

        print "Block: '%s' File: %s" % (self.funcId, self.filename)
        print "  The function with name '%s' is not defined." % (self.funcName)
        self.usecount = 1
        

class CStdout:
    def write(self, str):
        print str

    def close(self):
        pass

class CNullOut:
    def write(self, str):
        pass

    def close(self):
        pass

class State:
    def __init__(self, filename):
        self.filename = filename
        self._f = open(filename)
        self.line = 0
        self.plugins = []
        self.plugfuncs = []

        # these fields need not be stored in CPlugin after they are parsed
        self.pluginTag = ""
        self.pluginAttrs = "" # except id

    def readline(self):
        self.line += 1
        return self._f.readline()

    @property
    def shortFilename(self):
        p = os.path
        return p.join(p.basename(p.dirname(self.filename)), p.basename(self.filename))

    @property
    def posStr(self):
        return "%s:%d" % (self.shortFilename, self.line)
    

def parseStartup(state, plugin):
    if plugin.codeStartup == None: plugin.codeStartup = []
    while True:
        ln = state.readline()
        if ln == "":
            plugin.errors.append("%s: Missing tag: </STARTUP>" % state.posStr)
            break
        mo = re.match(r'''\s*"\s*</STARTUP>''', ln)
        if mo != None: return ln
        plugin.codeStartup.append(ln.rstrip())
    if ln == None or ln == "":
        return None
    return ln

def parsePlugin(state, plugin, moPlugin):
    if plugin.codePlugin == None: plugin.codePlugin = []
    mo = re.search(r'''\brequire\s*=\s*["']([^"']+)["']''', state.pluginAttrs)
    if mo == None: plugin.featureExpr = ""
    else: plugin.featureExpr = mo.group(1).replace(" ", "")

    while True:
        ln = state.readline()
        if ln == "":
            plugin.errors.append("%s: Missing tag: </VIMPLUGIN>" % state.posStr)
            break
        mo = re.match(r'''\s*"\s*</VIMPLUGIN>''', ln)
        if mo != None: return ln

        mo = re.match(r'''\s*"\s*<STARTUP>''', ln)
        if mo != None:
            ln = parseStartup(state, plugin)
            if ln == None: break
            continue
        plugin.codePlugin.append(ln.rstrip())
    if ln == None or ln == "": return None
    return ln

def parsePlugFunc(state, plugfn, moPlugFunc):
    mo = re.search(r'''\bname\s*=\s*["']([^"']+)["']''', state.pluginAttrs)
    if mo == None: plugfn.funcName = ""
    else: plugfn.funcName = mo.group(1).replace(" ", "").strip()
    if len(plugfn.funcName) > 0: plugfn.funcName = "s:" + plugfn.funcName

    plugfn.code = []

    while True:
        ln = state.readline()
        if ln == "":
            plugfn.errors.append("%s: Missing tag: </PLUGINFUNCTION>" % state.posStr)
            break
        mo = re.match(r'''\s*"\s*</PLUGINFUNCTION>''', ln)
        if mo != None: return ln
        plugfn.code.append(ln.rstrip())

    if ln == None or ln == "": return None
    return ln

def parseFile(fn):
    global config
    state = State(fn)
    # TODO: tags may span over multiple lines
    while True:
        ln = state.readline()
        if ln == "": break
        ln = ln.rstrip()
        mo = re.match(r'''\s*"\s*<VIMPLUGIN\s+id\s*=\s*["']([^"']+)["']([^>]*)>''', ln)
        if mo != None:
            plugin = CPlugin()
            plugin.pluginId = mo.group(1)
            plugin.filename = fn
            plugin.config = config.getPluginConf(plugin.pluginId)
            state.plugins.append(plugin)
            state.pluginAttrs = mo.group(2)
            state.pluginTag = ln
            ln = parsePlugin(state, plugin, mo)
            if ln == None: break
            continue
        mo = re.match(r'''\s*"\s*<PLUGINFUNCTION\s+id\s*=\s*["']([^"']+)["']([^>]*)>''', ln)
        if mo != None:
            plugfn = CPlugFunction()
            plugfn.funcId = mo.group(1)
            plugfn.filename = fn
            state.plugfuncs.append(plugfn)
            state.pluginAttrs = mo.group(2)
            ln = parsePlugFunc(state, plugfn, mo)
            if ln == None: break
            continue

    state._f.close()
    return state

def readOptions(args=None):
    usage = "Usage: %prog [options] file|dir [file|dir ...]"
    parser = optparse.OptionParser(usage)

    parser.add_option("-o", "--output", action="store", type="string", dest="outfile",
        help="Write the result to the given file. Write to stdout if not set.")
    parser.add_option("", "--one-per-file", action="store_const", const=1, dest="one_per_file", default=0,
        help="Write multiple files, one plugin per file. --output parameter is used for prefix.")
    #parser.add_option("", "--standalone", action="store_const", const=1, dest="standalone", default=0,
    #    help="Create a plugin that doesn't use vxlib/plugin.vim.")
    parser.add_option("", "--vxlibautogen", action="store_const", const=0, dest="usergenerated", default=1,
        help="Create a plugin for users that don't use the plugin generator.")
    parser.add_option("-c", "--config", action="store", type="string", dest="config",
        help="Read plugin settings from the configuration file.")
    parser.add_option("-u", "--update", action="store_const", const=1, dest="update_config", default=0,
        help="Update the configuration file given with '--update'.")
    parser.add_option("", "--indent", action="store", type="int", dest="indent", default=0,
        help="Indent the generated file with ex with the given indent size. Default=0 (off).")
    parser.add_option("", "--no-require", action="store_const", const=0, dest="add_require", default=1,
        help="Don't add the code to check if required features are present.")
    parser.add_option("-v", "--verbose", action="store", type="int", dest="verbose")
    parser.add_option("-q", "--quiet", action="store_const", const=0, dest="verbose")

    (options, args) = parser.parse_args(args)
    if options.verbose > 3: print "Options parsed"
    if len(args) < 1: parser.error("No files specifed.")
    if options.one_per_file and (options.outfile == None or len(options.outfile) < 1):
        parser.error("Option --one-per-file requires --output to be set.")
    return (options, args)

def walktree(top, callback):
    for f in os.listdir(top):
        pathname = os.path.join(top, f)
        mode = os.stat(pathname)[stat.ST_MODE]
        if stat.S_ISDIR(mode): walktree(pathname, callback)
        elif stat.S_ISREG(mode): callback(pathname)

def getFileList(args):
    files = []
    def addFile(fn):
        fn = os.path.abspath(fn)
        if not fn in files: files.append(fn)
    for fsp in args:
        mode = os.stat(fsp)[stat.ST_MODE]
        if stat.S_ISDIR(mode): walktree(fsp, addFile)
        elif stat.S_ISREG(mode): addFile(fsp)
    return files

def processFileList(files):
    plugins = []
    functions = []
    for fn in files:
        if fn.endswith(".vim"):
            state = parseFile(fn)
            plugins.extend(state.plugins)
            functions.extend(state.plugfuncs)
    return plugins, functions

def indentWithVim(fname, indent):
    try:
        os.system('vim +"set ft=vim sw=%d ts=8 et" +"norm gg=G" +"wq!" "%s"' % (indent, fname))
    except: pass

def markUsedFuctions(plugins, functions):
    for fn in functions: fn.resetUseCount()
    for pl in plugins:
        text = ("\n".join(pl.codePlugin)) + "\n" + ("\n".join(pl.codeStartup))
        for fn in functions:
            if fn.isUsed(): continue
            if text.find(fn.funcName) >= 0:
                fn.usecount += 1
    pass

def writePluginCode(plugins, functions):
    global options, config
    if options.outfile == "": out = CStdout()
    else: out = open(options.outfile, "w")
    markUsedFuctions(plugins, functions)
    writer = CPluginWriter_A()
    writer.writeFileHead(out)
    writer.writePluginFunctions(functions, out)
    writer.writePluginCode(plugins, out)
    writer.writeFileTail(out)
    out.close()

    if options.indent > 0 and options.outfile != "":
        indentWithVim(options.outfile, options.indent)

def writeSeparatePlugins(plugins, functions):
    global options, config
    if options.outfile == "": return
    base = options.outfile
    (base, ext) = os.path.splitext(base)
    for i,pl in enumerate(plugins):
        plname = pl.varName.strip("_")
        options.outfile = "%s%s%s" % (base, plname, ext)
        writePluginCode([pl], functions)

def test_split_plugin_code(plugins, functions):
    global options, config
    np = 1
    if options.outfile == "": return
    i = 0
    base = options.outfile
    while i * np < len(plugins):
        batch = plugins[i*np:(i+1)*np]
        options.outfile = base + ("%d.vim" % i)
        writePluginCode(batch, functions)
        i+=1

def main(args=None):
    global options, config
    options, args = readOptions(args)
    config = plugconf.CPluginConfig()
    if options.config != None and options.config != "" and os.path.exists(options.config):
        config.loadConfig(options.config)
    config.getPluginConf("default")

    lst = getFileList(args)
    if len(lst) < 1:
        print "No files to process."
        return

    plugins, functions = processFileList(lst)
    if options.one_per_file:
        writeSeparatePlugins(plugins, functions)
        # test_split_plugin_code(plugins, functions)
    else:
        writePluginCode(plugins, functions)

    if options.config != "" and options.update_config:
        try:
            config.saveConfig(options.config)
        except Exception as e:
            print "Exception: %s" % e

if __name__ == "__main__":
    main()