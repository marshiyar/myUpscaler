"""Private lossless stage and supervised native CPU export acceptance checks.

Uses existing pinned FFmpeg8.1.2 in Test.app; host ffprobe9 reads evidence.
No downloads, models, GPU or UI. All subprocesses execute sequentially.
"""
from pathlib import Path
from fractions import Fraction
import json
import os
import signal
import subprocess
import sys
import time
import selectors

integration = Path(sys.argv[1]).resolve()
folder = integration/'evidence/media-tests'
folder.mkdir(exist_ok=True)
macos = integration/'Test.app/Contents/MacOS'
ffmpeg = macos/'ThirdParty/FFmpeg/ffmpeg'
helper = macos/'up60p-neo-media'
driver = macos/'native-driver'
probe = '/opt/homebrew/bin/ffprobe'
results = []
def command(args, code=0, timeout=15, env=None):
    start=time.monotonic()
    result=subprocess.run([str(a) for a in args],capture_output=True,text=True,timeout=timeout,env=env)
    results.append({'command':[str(a) for a in args], 'exit':result.returncode,
                    'seconds':time.monotonic()-start,'stdout':result.stdout,'stderr':result.stderr})
    assert result.returncode==code, results[-1]
    return result
def info(path):
    return json.loads(command([probe,'-v','error','-show_streams','-show_packets','-show_data_hash','sha256','-of','json',path]).stdout)
def videoPackets(data):
    return [(p['pts'],p['dts'],p.get('duration')) for p in data['packets'] if p['codec_type']=='video']
def audioPackets(data):
    return [(p['stream_index'],p['pts'],p['dts'],p.get('duration'),p['data_hash']) for p in data['packets'] if p['codec_type']=='audio']
def source(name,fmt):
    path=folder/(name+'.nut')
    command([ffmpeg,'-v','error','-threads','1','-filter_threads','1','-copyts','-f','lavfi','-i',
        'testsrc2=size=66x34:rate=24:duration=1','-itsoffset','3.1','-f','lavfi','-i','sine=frequency=440:duration=1.6',
        '-itsoffset','3.2','-f','lavfi','-i','sine=frequency=880:duration=1.7',
        '-vf',r'select=mod(n\,3),setpts=PTS+3/TB,format='+fmt,'-fps_mode','passthrough',
        '-map','0:v:0','-map','1:a:0','-map','2:a:0','-c:v','rawvideo','-c:a','pcm_s16le',
        '-metadata:s:v:0','neo.color_primaries=1','-metadata:s:a:0','title=first',
        '-metadata:s:a:1','title=second','-f','nut','-y',path])
    return path
for fmt in ['yuv420p','yuv422p10le','yuv444p16le']:
    before=source(fmt,fmt);after=folder/(fmt+'-neo.nut')
    after.unlink(missing_ok=True)
    command([helper,before,after,15,128,96,32])
    a,b=info(before),info(after)
    assert videoPackets(a)==videoPackets(b),(fmt,'PTS/DTS/duration changed')
    assert audioPackets(a)==audioPackets(b),(fmt,'Audio packet bytes/timestamps changed')
    assert len(a['streams'])==len(b['streams'])==3
    for original,output in zip(a['streams'],b['streams']):
        for key in ['codec_name','pix_fmt','sample_rate','channels','time_base','sample_aspect_ratio','disposition','tags']:
            assert original.get(key)==output.get(key),(fmt,key,original.get(key),output.get(key))
    assert videoPackets(a)[0][0]>0
    assert len(videoPackets(a))==16
    assert [p['data_hash'] for p in a['packets'] if p['codec_type']=='video'] != [p['data_hash'] for p in b['packets'] if p['codec_type']=='video']

# Native placement/export primary, secondary, both, 10-bit, still, and batch.
fixture=Path('/Users/ash/.codex/2026-10-01/task-2/design-evidence/ui-fixture.mp4')
for mode,depth in [('primary','8'),('secondary','8'),('both','8'),('primary','10')]:
    output=folder/(mode+depth);output.mkdir(exist_ok=True)
    run=command([driver,mode,fixture,output,depth])
    assert run.stderr.count('Neo F3kdb: 24 frames;')==(2 if mode=='both' else 1)
    exported=output/'ui-fixture_[restored].mp4'
    data=info(exported)
    assert len(videoPackets(data))==24
    assert data['streams'][0]['pix_fmt']==('yuv420p10le' if depth=='10' else 'yuv420p')

# Specified color tags survive native final encoding; audio tracks/offsets stay.
colorSource=folder/'colors.mp4'
command([ffmpeg,'-v','error','-threads','1','-filter_threads','1','-copyts','-i',folder/'yuv420p.nut',
         '-map','0:v','-map','0:a','-c:v','libx264','-preset','ultrafast','-c:a','aac',
         '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-y',colorSource])
colorOut=folder/'colors-output';colorOut.mkdir(exist_ok=True)
command([driver,'both',colorSource,colorOut,'8'])
original,output=info(colorSource),info(colorOut/'colors_[restored].mp4')
for key in ['color_primaries','color_transfer','color_space','color_range','chroma_location']:
    assert original['streams'][0].get(key)==output['streams'][0].get(key),(key,original['streams'][0],output['streams'][0])
assert len(original['streams'])==len(output['streams'])==3
for a,b in zip(videoPackets(original),videoPackets(output)):
    ta=float(a[0])*Fraction(original['streams'][0]['time_base'])
    tb=float(b[0])*Fraction(output['streams'][0]['time_base'])
    assert abs(ta-tb)<.0001,(ta,tb)
for a,b in zip(original['streams'][1:],output['streams'][1:]):
    assert abs(float(a['start_time'])-float(b['start_time']))<.025,(a,b)
    assert abs(float(a['duration'])-float(b['duration']))<.05,(a,b)

image=folder/'still.jpg' # JPEG decodes to YUV; RGB/alpha sources are explicitly unsupported.
command([ffmpeg,'-v','error','-threads','1','-i',fixture,'-frames:v','1','-y',image])
imageOut=folder/'still-output';imageOut.mkdir(exist_ok=True)
command([driver,'both',image,imageOut])
assert (imageOut/'still_[restored].png').stat().st_size>0
batch=folder/'batch';batch.mkdir(exist_ok=True)
(batch/'one.png').unlink(missing_ok=True);(batch/'two.png').unlink(missing_ok=True)
(batch/'one.jpg').write_bytes(image.read_bytes());(batch/'two.jpg').write_bytes(image.read_bytes())
batchOut=folder/'batch-output';batchOut.mkdir(exist_ok=True)
command([driver,'primary',batch,batchOut])
assert len(list(batchOut.glob('*.png')))==2

# Zero-threshold genuine selection is an exact numerical bypass, including
# original full/limited range graph negotiation. It creates no raw boundary.
for colorRange in ['tv','pc']:
    sourceFile=folder/('neutral-'+colorRange+'.mp4')
    command([ffmpeg,'-v','error','-threads','1','-filter_threads','1','-i',fixture,
             '-c:v','libx264','-preset','ultrafast','-color_primaries','bt709','-color_trc','bt709',
             '-colorspace','bt709','-color_range',colorRange,'-y',sourceFile])
    outputs=[]
    for mode,profile in [('bypass','8'),('primary','neutral-f3')]:
        out=folder/('neutral-'+colorRange+'-'+mode);out.mkdir(exist_ok=True)
        run=command([driver,mode,sourceFile,out,profile])
        assert 'Neo F3kdb starting:' not in run.stderr
        exported=out/(sourceFile.stem+'_[restored].mp4')
        raw=folder/('neutral-'+colorRange+'-'+mode+'.yuv')
        command([ffmpeg,'-v','error','-threads','1','-i',exported,'-f','rawvideo','-pix_fmt','yuv420p','-y',raw])
        outputs.append(raw.read_bytes())
    assert outputs[0]==outputs[1],colorRange+' neutral split changed decoded baseline pixels'

# Reject an RGB still before work and preserve its existing final output.
rgbImage=folder/'rgb.png'
command([ffmpeg,'-v','error','-threads','1','-i',fixture,'-frames:v','1','-y',rgbImage])
rgbOut=folder/'rgb-output';rgbOut.mkdir(exist_ok=True)
rgbFinal=rgbOut/'rgb_[restored].png';rgbFinal.write_bytes(b'previous RGB export')
command([driver,'primary',rgbImage,rgbOut],code=3)
assert rgbFinal.read_bytes()==b'previous RGB export' and not list(rgbOut.glob('*.neo-*'))

# Reject unsupported/invalid requests and preserve existing final files.
protected=folder/'protected';protected.mkdir(exist_ok=True)
destination=protected/'ui-fixture_[restored].mp4';destination.write_bytes(b'previous export sentinel')
saved=destination.read_bytes()
command([driver,'primary',fixture,protected,'invalid'],code=1)
assert destination.read_bytes()==saved and not list(protected.glob('*.neo-*'))
for delay in [1,60,120]:
    destination.write_bytes(saved)
    result=command([driver,'both',fixture,protected,'8',delay],code=5) # up60p.h UP60P_ERR_CANCELLED
    assert 'cancelled' in result.stderr.lower()
    assert destination.read_bytes()==saved
    assert not list(protected.glob('*.neo-*'))

# Cancellation from the terminal native callback happens after rename but
# before process_path returns. The explicit committed outcome must survive.
destination.write_bytes(saved)
afterCommit = command([driver,'primary',fixture,protected,'8'],
                      env={**os.environ,'UP60P_TEST_CANCEL_AFTER_DONE':'1'})
assert 'Native result: UP60P_OK_COMMITTED' in afterCommit.stderr
assert 'Processing cancelled.' not in afterCommit.stderr
assert len(videoPackets(info(destination))) == 24
assert destination.read_bytes() != saved and not list(protected.glob('*.neo-*'))

# Helper owns/reaps its work under the production supervisor on owner EOF.
temporary=folder/'owner-exit.nut';temporary.unlink(missing_ok=True)
owner=subprocess.Popen([str(macos/'up60p-neo-supervisor'),str(folder/'yuv444p16le.nut'),str(temporary),'15','128','96','32'],
                       stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
owner.stdin.close();owner.wait(timeout=3)
assert owner.returncode==125
assert not temporary.exists()

# A real native owner killed during the core leaves final output unchanged.
# The registered supervisor reaps its child before removing only job-owned files.
destination.write_bytes(saved)
forced=subprocess.Popen([str(driver),'both',str(fixture),str(protected),'8'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
reader=selectors.DefaultSelector();reader.register(forced.stderr,selectors.EVENT_READ)
pending=b'';started=False;deadline=time.monotonic()+5
while time.monotonic()<deadline and not started:
    for key,_ in reader.select(.05):
        block=os.read(key.fileobj.fileno(),4096)
        if not block: break
        pending+=block;started=b'Neo F3kdb starting:' in pending
assert started,pending.decode(errors='replace')
forced.kill();forced.wait(timeout=3)
reader.close()
deadline=time.monotonic()+3
while list(protected.glob('*.neo-*')) and time.monotonic()<deadline: time.sleep(.01)
assert destination.read_bytes()==saved
assert not list(protected.glob('*.neo-*')),'Active-stage owner death left private temporary media'

(folder/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS: lossless 8/10/16 stage PTS/audio/layout; native primary/secondary/both/10bit/still/batch/color/export cancellation, owner EOF and active-core force-quit cleanup')
