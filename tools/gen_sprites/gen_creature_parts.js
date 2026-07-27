const fs = require('fs');
const zlib = require('zlib');
const path = require('path');

const S = 16;
const OUT = path.join(__dirname, '..', '..', 'sprites', 'parts');

if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

function createPNG(pixels) {
    const raw = Buffer.alloc(S * (1 + S * 4));
    for (let y = 0; y < S; y++) {
        raw[y * (1 + S * 4)] = 0;
        for (let x = 0; x < S; x++) {
            const src = (y * S + x) * 4;
            const dst = y * (1 + S * 4) + 1 + x * 4;
            raw[dst] = pixels[src];
            raw[dst + 1] = pixels[src + 1];
            raw[dst + 2] = pixels[src + 2];
            raw[dst + 3] = pixels[src + 3];
        }
    }
    const compressed = zlib.deflateSync(raw);
    function crc32(buf) {
        let c;
        const table = [];
        for (let n = 0; n < 256; n++) {
            c = n;
            for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
            table[n] = c;
        }
        c = 0xFFFFFFFF;
        for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
        return (c ^ 0xFFFFFFFF) >>> 0;
    }
    function chunk(type, data) {
        const len = Buffer.alloc(4);
        len.writeUInt32BE(data.length, 0);
        const typeAndData = Buffer.concat([Buffer.from(type, 'ascii'), data]);
        const crc = Buffer.alloc(4);
        crc.writeUInt32BE(crc32(typeAndData), 0);
        return Buffer.concat([len, typeAndData, crc]);
    }
    const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    const ihdrData = Buffer.alloc(13);
    ihdrData.writeUInt32BE(S, 0);
    ihdrData.writeUInt32BE(S, 4);
    ihdrData[8] = 8; ihdrData[9] = 6;
    return Buffer.concat([sig, chunk('IHDR', ihdrData), chunk('IDAT', compressed), chunk('IEND', Buffer.alloc(0))]);
}

function blank() { return Buffer.alloc(S * S * 4); }

function rgba(r,g,b,a) { return {r,g,b,a}; }
function gray(v,a) { return {r:v,g:v,b:v,a:a!==undefined?a:255}; }

function set(buf,x,y,c) {
    if (x<0||x>=S||y<0||y>=S) return;
    const i = (y*S+x)*4;
    const sa = c.a/255, da = buf[i+3]/255, oa = sa+da*(1-sa);
    if (oa===0) { buf[i]=buf[i+1]=buf[i+2]=buf[i+3]=0; return; }
    buf[i]   = Math.round((c.r*sa + buf[i]*da*(1-sa))/oa);
    buf[i+1] = Math.round((c.g*sa + buf[i+1]*da*(1-sa))/oa);
    buf[i+2] = Math.round((c.b*sa + buf[i+2]*da*(1-sa))/oa);
    buf[i+3] = Math.round(oa*255);
}

function rect(buf,x,y,w,h,c) { for(let dy=0;dy<h;dy++) for(let dx=0;dx<w;dx++) set(buf,x+dx,y+dy,c); }
function circle(buf,cx,cy,r,c) { for(let dy=-r;dy<=r;dy++) for(let dx=-r;dx<=r;dx++) if(dx*dx+dy*dy<=r*r) set(buf,cx+dx,cy+dy,c); }
function tri(buf,x1,y1,x2,y2,x3,y3,c) {
    for(let y=0;y<S;y++) for(let x=0;x<S;x++) {
        const d1=(x-x1)*(y2-y1)-(y-y1)*(x2-x1);
        const d2=(x-x2)*(y3-y2)-(y-y2)*(x3-x2);
        const d3=(x-x3)*(y1-y3)-(y-y3)*(x1-x3);
        if((d1>=0&&d2>=0&&d3>=0)||(d1<=0&&d2<=0&&d3<=0)) set(buf,x,y,c);
    }
}

function line(buf,x1,y1,x2,y2,c) {
    const dx=Math.abs(x2-x1), dy=Math.abs(y2-y1);
    const sx=x1<x2?1:-1, sy=y1<y2?1:-1;
    let err=dx-dy;
    let x=x1,y=y1;
    while(true) {
        set(buf,x,y,c);
        if(x===x2&&y===y2) break;
        const e2=2*err;
        if(e2>-dy) { err-=dy; x+=sx; }
        if(e2<dx) { err+=dx; y+=sy; }
    }
}

function circleLine(buf,cx,cy,r,c) {
    let x=0,y=r,d=3-2*r;
    while(x<=y) {
        for(const [dx,dy] of [[x,y],[y,x],[y,-x],[x,-y],[-x,-y],[-y,-x],[-y,x],[-x,y]]) set(buf,cx+dx,cy+dy,c);
        if(d<0) d+=4*x+6; else { d+=4*(x-y)+10; y--; }
        x++;
    }
}

function save(name, buf) {
    fs.writeFileSync(path.join(OUT, name + '.png'), createPNG(buf));
    console.log('OK  ' + name);
}

// ═══════════════════════════════════════════
// Creature parts — grayscale (tinted by Love2D setColor)
// head_slow has its own ice-blue color
// ═══════════════════════════════════════════

// ── chassis: mobility ──
// walking
const cw = blank();
tri(cw, 2,9, 14,9, 11,15, gray(255));
tri(cw, 2,9, 14,9, 5,15, gray(255));
rect(cw, 4,12, 2,3, gray(179));
rect(cw, 10,12, 2,3, gray(179));
save('chassis_walking', cw);

// hovering
const ch = blank();
tri(ch, 1,9, 15,9, 12,15, gray(255));
tri(ch, 1,9, 15,9, 4,15, gray(255));
tri(ch, 0,10, 3,10, 2,14, gray(204, 153));
tri(ch, 0,10, 3,10, 0,13, gray(204, 153));
tri(ch, 16,10, 13,10, 14,14, gray(204, 153));
tri(ch, 16,10, 13,10, 16,13, gray(204, 153));
save('chassis_hovering', ch);

// teleport
const ct = blank();
tri(ct, 2,9, 14,9, 11,15, gray(255));
tri(ct, 2,9, 14,9, 5,15, gray(255));
circleLine(ct, 8,12, 2, gray(255, 128));
circleLine(ct, 8,12, 4, gray(255, 128));
circleLine(ct, 8,12, 6, gray(255, 128));
save('chassis_teleport', ct);

// ── body: health ──
for (let h = 1; h <= 3; h++) {
    const b = blank();
    const size = h === 1 ? 5 : h === 2 ? 7 : 9;
    const xOff = Math.floor((S - size) / 2);
    const yOff = 11 - size;
    rect(b, xOff, yOff, size, size, gray(255));
    save('body_' + h, b);
}

// ── hands: attack set ──
const hg = blank();
circle(hg, 2, 8, 2, gray(255));
circle(hg, 14, 8, 2, gray(255));
circle(hg, 1, 7, 1.5, gray(153, 128));
circle(hg, 15, 7, 1.5, gray(153, 128));
save('hands_ghost', hg);

const hz = blank();
rect(hz, 1, 8, 3, 3, gray(255));
rect(hz, 12, 8, 3, 3, gray(255));
save('hands_zombie', hz);

const hl = blank();
tri(hl, 1,11, 4,6, 4,11, gray(255));
tri(hl, 15,11, 12,6, 12,11, gray(255));
save('hands_lich', hl);

const hb = blank();
rect(hb, 0, 7, 4, 4, gray(255));
rect(hb, 12, 7, 4, 4, gray(255));
save('hands_brute', hb);

const hla = blank();
tri(hla, 0,12, 4,6, 5,12, gray(255));
tri(hla, 16,12, 12,6, 11,12, gray(255));
save('hands_lancer', hla);

const hd = blank();
tri(hd, 0,10, 4,6, 5,10, gray(255));
tri(hd, 16,10, 12,6, 11,10, gray(255));
save('hands_dervish', hd);

// ── head: aura ──
const hn = blank();
circle(hn, 8, 3, 3, gray(255));
save('head_none', hn);

// slow aura has fixed ice-blue color (not tinted)
const hs = blank();
circle(hs, 8, 3, 4, rgba(153, 204, 255, 255));
circleLine(hs, 8, 3, 1.5, rgba(255, 255, 255, 102));
circleLine(hs, 8, 3, 3, rgba(255, 255, 255, 102));
circleLine(hs, 8, 3, 4, rgba(255, 255, 255, 102));
save('head_slow', hs);

console.log('\nDone! ' + (fs.readdirSync(OUT).length) + ' creature part sprites generated.');
