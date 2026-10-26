"""Build original local SVG city covers. No remote image requests or licenses."""
from html import escape
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.international_catalog import AIRPORTS

LANDMARKS={
 'SIN':'<path d="M210 620V400h65v220m35 0V385h65v235m35 0V390h65v230" fill="#e7f4ed"/><path d="M175 385q165 60 335-5l-28 45q-155 50-282 3Z" fill="#cae3da"/><circle cx="555" cy="510" r="95" stroke="#e3f5eb" stroke-width="8" fill="none"/><path d="m555 415-50 200m50-200 50 200M460 510h190" stroke="#d6ece1" stroke-width="4"/>',
 'NRT':'<path d="m110 550 260-285 280 285Z" fill="#9dadbc"/><path d="m280 365 90-100 100 105-55-13-42 23-46-20Z" fill="#f3f4f3"/><path d="M225 625V485h280v140M255 555h220m-240-70 270 0-35-30H270Z" stroke="#8c313b" stroke-width="22" fill="none"/><path d="M290 625V425h180v200m-215-200h250l-45-35H300Z" fill="#ebc7a4"/><path d="M250 430h260l-40-35H290Zm-30 80h320l-50-35H270Z" fill="#713f47"/>',
 'CDG':'<path d="M380 250 285 650h60l35-75 35 75h60Zm0 85-30 180h60Zm-45 205h90m-110 65h130" stroke="#fbdfb4" stroke-width="15" stroke-linejoin="round" fill="none"/><path d="M368 270h24v-55h-24Z" fill="#fbdfb4"/>',
 'SYD':'<path d="M100 640h550v30H100Z" fill="#d5e7df"/><path d="m140 640 90-225 85 225Zm100 0 110-290 100 290Zm115 0 150-210 70 210Zm115 0 120-150 55 150Z" fill="#f8eee1"/><path d="m230 415 20 225m100-290 35 290m120-210-70 210" stroke="#b6cfcd" stroke-width="5"/>',
 'DXB':'<path d="M365 640V370h-20v-40h20V210h15V115h8v160h18v100h22v265Z" fill="#e7dcc7"/><path d="M130 640V410l45-65 45 65v230m310 0V330l45-35 45 35v310" fill="#9abbb6"/><path d="M275 640V400h55v240m120 0V465h45v175" fill="#bfd1c5"/>',
 'ICN':'<path d="M365 625V375h30v250m-14-250v-125m-48 125h100l-12 60h-77Z" stroke="#f2d9ba" stroke-width="12" fill="#e6c7a2"/><path d="m90 650 190-90 100 30 200-75 100 135Z" fill="#557d76"/><path d="M200 625V540h110v85m-130-85 150 0-35-30h-80Z" fill="#dde5d7"/>',
 'LHR':'<path d="M260 650V320h110v330m-125-330 70-100 70 100Z" fill="#d2c3a8"/><circle cx="315" cy="380" r="35" fill="#f8e9bb"/><path d="M315 356v24l17 10" stroke="#3c5c5f" stroke-width="6"/><circle cx="540" cy="500" r="105" stroke="#d7e4df" stroke-width="9" fill="none"/><path d="m540 395-60 255m60-255 60 255M435 500h210" stroke="#d7e4df" stroke-width="4"/>',
 'BKK':'<path d="M165 650V510h160v140m115 0V470h150v180" fill="#eed7aa"/><path d="m150 515 95-75 95 75m85-35 90-85 90 85" fill="#b98659"/><path d="M340 650V410h85v240m-105-240 62-145 63 145m-63-145V185" stroke="#f2d6a3" stroke-width="12" fill="#e5bd7a"/>',
 'SFO':'<path d="M0 590q380-130 760 0M210 650V370h45v280m250 0V360h45v290" stroke="#da785c" stroke-width="17" fill="none"/><path d="M235 390q130 235 295-10M0 540q130 80 235-150m295-10q90 170 230 120" stroke="#efb395" stroke-width="7" fill="none"/>',
}


def main():
    folder=Path(__file__).resolve().parents[1]/'app/static/images/destinations';folder.mkdir(parents=True,exist_ok=True)
    palettes=[('#174b66','#8dc7ce','#f5d69d'),('#365d69','#c2d8cf','#f6c8ad'),('#4e596b','#b8c3d5','#edcc9d'),('#236c70','#a3d4cf','#f5e1b7'),('#786553','#ddbb8f','#f7e4a9'),('#394c68','#b4c2d4','#f2c39a')]
    for i,a in enumerate(AIRPORTS):
        code,city=a[:2];top,sky,sun=palettes[i%len(palettes)]
        buildings=''.join(f'<rect x="{20+j*65}" y="{510+(i*13+j*29)%110}" width="{38+(j*7+i)%20}" height="{180-(i*13+j*29)%110}" rx="3"/>' for j in range(12))
        landmark=LANDMARKS.get(code,'<g fill="#d5e5dd" opacity=".8">'+buildings+'</g>')
        # Every cover varies its skyline, colors, coast and sun; none is a photo.
        svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="760" height="950" viewBox="0 0 760 950" role="img" aria-label="Minh họa {escape(city)}">
<defs><linearGradient id="s" x2="0" y2="1"><stop stop-color="{top}"/><stop offset="1" stop-color="{sky}"/></linearGradient><linearGradient id="w" x2="0" y2="1"><stop stop-color="{sky}"/><stop offset="1" stop-color="{top}"/></linearGradient><linearGradient id="v" x2="0" y2="1"><stop offset=".5" stop-color="#123d3a" stop-opacity="0"/><stop offset="1" stop-color="#123d3a" stop-opacity=".8"/></linearGradient></defs>
<path fill="url(#s)" d="M0 0h760v950H0Z"/><circle cx="{175+i*17%410}" cy="{235+i*19%95}" r="{82+i%4*12}" fill="{sun}" opacity=".78"/>
<path d="M-20 385Q170 {290+i*3} 310 365T800 315" stroke="#fff" stroke-opacity=".17" stroke-width="45" fill="none"/><g fill="{top}" opacity=".25">{buildings}</g>
{landmark}<path d="M0 663Q180 {640+i%5*10} 380 673T760 650V950H0Z" fill="url(#w)"/>
<path d="M90 710h145m90 36h195m-420 28h250m150 35h180m-460 25h130" stroke="#fff" stroke-opacity=".22" stroke-width="3" stroke-linecap="round"/>
<path d="M0 0h760v950H0Z" fill="url(#v)"/><g stroke="#fff" stroke-opacity=".15" fill="none"><circle cx="690" cy="90" r="100"/><circle cx="690" cy="90" r="135"/></g></svg>'''
        (folder/(code+'.svg')).write_text(svg,encoding='utf-8')
    print(f'Built {len(AIRPORTS)} original local destination covers.')


if __name__=='__main__':main()
