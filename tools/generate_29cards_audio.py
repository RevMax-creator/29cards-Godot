import os, math, subprocess, pathlib
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'assets' / 'audio'
SFX = ROOT / 'sfx'
VOICE = ROOT / 'voice'
SFX.mkdir(parents=True, exist_ok=True)
VOICE.mkdir(parents=True, exist_ok=True)
SR = 48000
rng = np.random.default_rng(29029)

def env_exp(n, attack=0.005, decay=0.08, sustain=0.0, release=None):
    t=np.arange(n)/SR
    a=np.clip(t/max(attack,1e-5),0,1)
    d=np.exp(-np.maximum(t-attack,0)/max(decay,1e-5))
    return np.maximum(a*d, sustain)

def band_noise(n, lo=500, hi=8000):
    x=rng.normal(0,1,n)
    lo=max(30,lo); hi=min(SR*0.48,hi)
    sos=butter(3,[lo,hi],btype='bandpass',fs=SR,output='sos')
    y=sosfilt(sos,x)
    m=np.max(np.abs(y)) or 1
    return y/m

def lowpass(x, cutoff):
    return sosfilt(butter(2, cutoff, btype='lowpass', fs=SR, output='sos'), x)

def highpass(x, cutoff):
    return sosfilt(butter(2, cutoff, btype='highpass', fs=SR, output='sos'), x)

def tone(freq, dur, amp=0.3, kind='sine', phase=0):
    n=max(1,int(SR*dur)); t=np.arange(n)/SR
    if kind=='triangle':
        y=2/np.pi*np.arcsin(np.sin(2*np.pi*freq*t+phase))
    elif kind=='softsquare':
        y=np.tanh(2.6*np.sin(2*np.pi*freq*t+phase))
    else:
        y=np.sin(2*np.pi*freq*t+phase)
    return y*amp

def place(buf, sig, start, gain=1.0, pan=0.0):
    i=max(0,int(start*SR)); j=min(len(buf),i+len(sig))
    if j<=i:return
    s=sig[:j-i]*gain
    # Equal-power stereo pan.
    l=math.sqrt((1-pan)*0.5); r=math.sqrt((1+pan)*0.5)
    buf[i:j,0]+=s*l; buf[i:j,1]+=s*r

def makebuf(seconds): return np.zeros((int(seconds*SR),2),dtype=np.float64)

def card_flick(dur=0.13, strength=1.0):
    n=int(dur*SR); t=np.arange(n)/SR
    noise=band_noise(n,700,11000)
    body=lowpass(band_noise(n,120,2400),1800)
    e=np.exp(-t/(dur*0.26))*np.minimum(1,t/(dur*0.06))
    crack=0.18*np.sin(2*np.pi*(1800-900*t/dur)*t)*e
    return (0.62*noise+0.23*body+crack)*e*strength

def click_impact(dur=0.09, amp=0.45):
    n=int(dur*SR); t=np.arange(n)/SR
    noise=band_noise(n,900,12000)
    thump=np.sin(2*np.pi*(145-60*t/dur)*t)*np.exp(-t/0.018)
    return amp*(0.42*noise*np.exp(-t/0.019)+0.72*thump)

def sound_card_deal():
    b=makebuf(0.19)
    place(b,click_impact(0.075,0.42),0.0,1.0,-0.08)
    place(b,card_flick(0.12,0.5),0.018,0.65,0.08)
    return b

def sound_deck_shuffle():
    """Warm, physical paper-card riffle: broad soft scrapes, not electronic zaps."""
    b = makebuf(2.05)

    # Broad paper-on-paper movement. Keep the spectrum deliberately dark and
    # avoid tonal sweeps or sharp transient bursts that read as sci-fi weapons.
    passes = [
        (0.02, 0.72, 150, 2850, -0.28, 0.27),
        (0.36, 0.78, 180, 3250, 0.24, 0.25),
        (0.88, 0.68, 130, 2500, -0.12, 0.22),
    ]
    for index, (start, dur, low, high, pan, gain) in enumerate(passes):
        n = int(dur * SR)
        t = np.arange(n) / SR
        paper = band_noise(n, low, high)
        paper = lowpass(paper, 2550)
        low_body = lowpass(band_noise(n, 90, 1050), 820)
        # Slow asymmetric envelope, lightly varied by hand-like friction.
        fade_in = np.clip(t / 0.12, 0.0, 1.0)
        fade_out = np.clip((dur - t) / 0.19, 0.0, 1.0)
        envelope = np.minimum(fade_in, fade_out) ** 0.72
        friction = 0.78 + 0.10 * np.sin(2 * np.pi * (3.1 + index * 0.35) * t)
        friction += 0.05 * np.sin(2 * np.pi * (7.4 + index * 0.2) * t + 0.7)
        place(b, (0.72 * paper + 0.28 * low_body) * envelope * friction,
              start, gain, pan)

    # Small, irregular card-edge flutter while the two packets interleave.
    # These are rounded, low-passed paper ticks rather than bright impacts.
    time_pos = 0.20
    while time_pos < 1.48:
        dur = float(rng.uniform(0.035, 0.072))
        n = int(dur * SR)
        t = np.arange(n) / SR
        grain = lowpass(band_noise(n, 220, 4200), 2850)
        attack = np.clip(t / 0.010, 0.0, 1.0)
        release = np.exp(-t / float(rng.uniform(0.034, 0.052)))
        place(b, grain * attack * release,
              time_pos, float(rng.uniform(0.075, 0.12)),
              float(rng.uniform(-0.38, 0.38)))
        time_pos += float(rng.uniform(0.082, 0.145))

    # A soft, padded deck-square at the end of the shuffle.
    n = int(0.13 * SR)
    t = np.arange(n) / SR
    tap_noise = lowpass(band_noise(n, 120, 2600), 1800)
    tap_body = np.sin(2 * np.pi * (105 - 28 * t / 0.13) * t)
    tap_env = np.exp(-t / 0.045)
    place(b, (0.30 * tap_noise + 0.70 * tap_body) * tap_env,
          1.70, 0.12, 0.02)
    return b

def sound_card_sort():
    b=makebuf(.72)
    for i in range(6):
        st=.02+i*.088
        place(b,card_flick(.15,.42),st,1.0,-.55+i*.22)
    place(b,click_impact(.07,.22),.57,1,0.05)
    return b

def sound_card_play():
    b=makebuf(.28)
    place(b,click_impact(.09,.55),0.0,1,-.08)
    place(b,card_flick(.20,.52),.028,.72,.14)
    place(b,tone(920,.045,.055),.008,1,.0)
    return b

def sound_trick_collect():
    b=makebuf(.82)
    for i in range(4):
        place(b,card_flick(.22,.46),.015+i*.06,1.0,-.42+i*.27)
    place(b,click_impact(.16,.30),.43,1,.0)
    place(b,tone(392,.22,.075),.47,1,.05)
    return b

def sound_turn():
    b=makebuf(.50)
    for st,f,a,d in [(0,740,.18,.22),(.13,988,.15,.29)]:
        n=int(d*SR); t=np.arange(n)/SR
        s=(np.sin(2*np.pi*f*t)+.22*np.sin(2*np.pi*f*2.01*t))*np.exp(-t/.11)
        place(b,s,st,a,0)
    return b

def sound_ui_click():
    b=makebuf(.11)
    place(b,tone(640,.055,.16)*np.exp(-np.arange(int(.055*SR))/SR/.025),0,1,0)
    place(b,click_impact(.045,.13),.012,1,0)
    return b

def sound_pass():
    b=makebuf(.21)
    x=band_noise(int(.18*SR),500,5000); t=np.arange(len(x))/SR
    place(b,x*np.exp(-t/.045)*.2,.015,1,0)
    return b

def sound_trump():
    b=makebuf(1.18)
    n=int(1.0*SR); t=np.arange(n)/SR
    sweep=np.sin(2*np.pi*(240*t+220*t*t))*np.sin(np.pi*t/1.0)*.24
    shimmer=band_noise(n,3000,11000)*np.sin(np.pi*t)*.075
    place(b,sweep+shimmer,.02,1,0)
    for i,f in enumerate([660,880,1320]):
        place(b,tone(f,.36,.085)*np.exp(-np.arange(int(.36*SR))/SR/.18),.53+i*.035,1,(-.25+i*.25))
    return b

def sound_trump_select():
    b=makebuf(.48)
    for i,f in enumerate([587.33,783.99]):
        d=.30; n=int(d*SR); t=np.arange(n)/SR
        sig=(np.sin(2*np.pi*f*t)+.12*np.sin(2*np.pi*2*f*t))*np.exp(-t/.14)
        place(b,sig,.025+i*.085,.095,(-.12+i*.24))
    return b

def sound_double(redouble=False):
    b=makebuf(.95 if redouble else .75)
    dur=.34; n=int(dur*SR); t=np.arange(n)/SR
    bass=(np.sin(2*np.pi*(82-20*t/dur)*t)+.35*np.sin(2*np.pi*164*t))*np.exp(-t/.12)
    place(b,bass,.015,.34,0)
    place(b,click_impact(.12,.42),.0,1,0)
    freqs=[440,554,659] if redouble else [330,415]
    for i,f in enumerate(freqs):
        d=.45; m=int(d*SR); tt=np.arange(m)/SR
        s=(np.sin(2*np.pi*f*tt)+.18*np.sin(4*np.pi*f*tt))*np.exp(-tt/.18)
        place(b,s,.28+i*.045,.09,(-.3+i*.25))
    return b

def sound_pair():
    b=makebuf(.82)
    for i,f in enumerate([523.25,659.25,783.99,1046.5]):
        d=.48; n=int(d*SR); t=np.arange(n)/SR
        s=(np.sin(2*np.pi*f*t)+.16*np.sin(2*np.pi*2*f*t))*np.exp(-t/.22)
        place(b,s,.03+i*.075,.12,(-.35+i*.22))
    return b

def sound_outcome(win=True, match=False):
    b=makebuf(1.55 if match else 1.0)
    if win:
        notes=[523.25,659.25,783.99,1046.5] if match else [523.25,659.25,783.99]
    else:
        notes=[392,349.23,293.66] if match else [392,329.63,261.63]
    base=.08
    for i,f in enumerate(notes):
        d=.7 if match else .48; n=int(d*SR); t=np.arange(n)/SR
        partial=np.sin(2*np.pi*f*t)+.16*np.sin(2*np.pi*2*f*t)
        e=np.exp(-t/(.34 if win else .24))
        place(b,partial*e,base+i*(.14 if match else .11),.12 if win else .10,-.36+i*.24)
    if not win:
        place(b,click_impact(.16,.16),.03,1,0)
    return b

def sound_error():
    b=makebuf(.35)
    d=.25; n=int(d*SR); t=np.arange(n)/SR
    s=(np.sin(2*np.pi*185*t)+.35*np.sin(2*np.pi*230*t))*np.exp(-t/.10)
    place(b,s,.02,.22,0)
    place(b,band_noise(n,400,2500)*np.exp(-t/.05),.02,.07,0)
    return b

bank={
 'deck_shuffle':sound_deck_shuffle,
 'card_deal':sound_card_deal,
 'card_sort':sound_card_sort,
 'card_play':sound_card_play,
 'trick_collect':sound_trick_collect,
 'turn_alert':sound_turn,
 'ui_click':sound_ui_click,
 'bid_pass':sound_pass,
 'trump_select':sound_trump_select,
 'trump_reveal':sound_trump,
 'double':lambda:sound_double(False),
 'redouble':lambda:sound_double(True),
 'pair_declared':sound_pair,
 'hand_win':lambda:sound_outcome(True,False),
 'hand_loss':lambda:sound_outcome(False,False),
 'match_win':lambda:sound_outcome(True,True),
 'match_loss':lambda:sound_outcome(False,True),
 'error':sound_error,
}

def write_ogg(path, audio, filters='alimiter=limit=0.92'):
    # audio is stereo float [-1,1]; keep headroom then encode Ogg Vorbis.
    peak=np.max(np.abs(audio)) or 1
    audio=np.clip(audio*(0.78/peak),-0.98,0.98)
    pcm=(audio*32767).astype('<i2')
    tmp=str(path)+'.wav'
    import wave
    with wave.open(tmp,'wb') as wf:
        wf.setnchannels(2); wf.setsampwidth(2); wf.setframerate(SR); wf.writeframes(pcm.tobytes())
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',tmp,'-af',filters,'-c:a','libvorbis','-q:a','4',str(path)],check=True)
    os.remove(tmp)

for name,fn in bank.items():
    arr=fn()
    write_ogg(SFX/f'{name}.ogg',arr)
    print('sfx',name,arr.shape[0]/SR)

# Spoken auction callouts. eSpeak is used offline so no API/network is required.
voice_filters='highpass=f=95,lowpass=f=7600,acompressor=threshold=-28dB:ratio=3.2:attack=5:release=90:makeup=9,loudnorm=I=-17:TP=-2:LRA=8,alimiter=limit=0.94'
for amount in range(15,29):
    phrase={15:'Fifteen!',16:'Sixteen!',17:'Seventeen!',18:'Eighteen!',19:'Nineteen!',20:'Twenty!',21:'Twenty one!',22:'Twenty two!',23:'Twenty three!',24:'Twenty four!',25:'Twenty five!',26:'Twenty six!',27:'Twenty seven!',28:'Twenty eight!'}[amount]
    wav=VOICE/f'bid_{amount}.wav'
    subprocess.run(['espeak','-v','en-us+m3','-s','168','-p','46','-a','185','-g','2','-w',str(wav),phrase],check=True)
    out=VOICE/f'bid_{amount}.ogg'
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(wav),'-af',voice_filters,'-ac','2','-c:a','libvorbis','-q:a','5',str(out)],check=True)
    wav.unlink()
    print('voice',phrase)

# Soft spoken pass marker for auction readability.
for name,phrase in [('pass','Pass!')]:
    wav=VOICE/f'{name}.wav'
    subprocess.run(['espeak','-v','en-us+m3','-s','158','-p','43','-a','150','-w',str(wav),phrase],check=True)
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(wav),'-af',voice_filters,'-ac','2','-c:a','libvorbis','-q:a','5',str(VOICE/f'{name}.ogg')],check=True)
    wav.unlink()

print('Generated',len(list(SFX.glob('*.ogg'))),'SFX and',len(list(VOICE.glob('*.ogg'))),'voice clips')
