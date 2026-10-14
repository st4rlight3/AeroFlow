"""Customer travel documents; never airline-valid documents."""
import os
from io import BytesIO
from pathlib import Path
from threading import Lock
from xml.sax.saxutils import escape
from datetime import timedelta
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.graphics.shapes import Drawing
from reportlab.graphics.barcode.qr import QrCodeWidget
from ..errors import ApiError

font_lock=Lock()

def font_name():
    with font_lock:
        if 'AeroFlowUnicode' not in pdfmetrics.getRegisteredFontNames():
            candidates=[os.getenv('PDF_FONT_PATH',''),str(Path(os.getenv('WINDIR','C:/Windows'))/'Fonts'/'arial.ttf'),'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']
            path=next((p for p in candidates if p and Path(p).is_file()),None)
            if not path: raise ApiError('Chưa cấu hình phông chữ Unicode cho PDF. Đặt PDF_FONT_PATH theo README.',503)
            pdfmetrics.registerFont(TTFont('AeroFlowUnicode',path))
    return 'AeroFlowUnicode'

def ticket_pdf(row,boarding=False):
    out=BytesIO(); font=font_name()
    style=ParagraphStyle('text',fontName=font,fontSize=11,leading=17,textColor=colors.HexColor('#163f38'))
    title=ParagraphStyle('title',parent=style,fontSize=22,leading=28,spaceAfter=15)
    def p(value,kind=style): return Paragraph(escape(str(value)),kind)
    def dt(value): return (value+timedelta(hours=7)).strftime('%H:%M %d/%m/%Y')+' (UTC+7)' if value else 'Chưa công bố'
    story=[p('AeroFlow Ultimate',title),p('THẺ LÊN MÁY BAY' if boarding else 'VÉ ĐIỆN TỬ',title),p('DEMO — NOT VALID FOR TRAVEL'),p('Mô phỏng học tập • Không có giá trị vận chuyển'),Spacer(1,8*mm)]
    fields=[('Mã đặt chỗ',row['PNR']),('Số vé',row['TicketNumber']),('Hành khách',row['FullName']),('Hành trình',row['OriginCode']+' → '+row['DestinationCode']),('Chuyến bay',row['FlightNumber']),('Khởi hành theo lịch',dt(row['DepartureTime'])),('Khởi hành dự kiến',dt(row['EstimatedDeparture'] or row['DepartureTime'])),('Đến theo lịch',dt(row['ArrivalTime'])),('Ghế / Hạng vé',row['SeatNumber']+' / '+row['FareName']),('Cửa lên máy bay',row['Gate'] or 'Chưa công bố'),('Trạng thái',row['TicketStatus'])]
    if not boarding:
        if row['BreakdownSource']=='DETAILED': fields.extend((k,f"{row[v]:,.0f} VND") for k,v in [('Giá cơ sở','BaseFare'),('Thuế','TaxAmount'),('Phí ghế','SeatFee')])
        fields.extend([('Dịch vụ bổ sung',f"{row['ExtrasAmount']:,.0f} VND"),('Giảm giá phân bổ',f"{row['DiscountAmount']:,.0f} VND"),('Giá trị vé sau ưu đãi',f"{row['PaidValue']:,.0f} VND")])
    grid=Table([[p(k),p(v)] for k,v in fields],colWidths=[60*mm,110*mm]);grid.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('BACKGROUND',(0,0),(-1,-1),colors.HexColor('#edf7f3')),('BOTTOMPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),6)]));story.append(grid)
    if boarding:
        # Opaque demo reference only: no name, passport, session or authentication secret.
        qr=QrCodeWidget('AEROFLOW-DEMO:'+row['Reference']); bounds=qr.getBounds(); size=100
        drawing=Drawing(size,size,transform=[size/(bounds[2]-bounds[0]),0,0,size/(bounds[3]-bounds[1]),0,0]);drawing.add(qr)
        story.extend([Spacer(1,4*mm),drawing,p('Mã tham chiếu: '+row['Reference'])])
    story.extend([Spacer(1,5*mm),p('Kiểm tra trạng thái mới nhất trên AeroFlow. PDF đã tải xuống không tự cập nhật khi vé hoặc chuyến bay thay đổi.')])
    SimpleDocTemplate(out,pagesize=(210*mm,297*mm),leftMargin=20*mm,rightMargin=20*mm,topMargin=18*mm,bottomMargin=18*mm,title='AeroFlow DEMO travel document',author='AeroFlow').build(story)
    out.seek(0);return out

def report_pdf(title,headers,rows):
    out=BytesIO();font=font_name();style=ParagraphStyle('report',fontName=font,fontSize=9,leading=13)
    paragraph=lambda value:Paragraph(escape(str(value)),style)
    data=[[paragraph(v) for v in headers]]+[[paragraph(v) for v in row] for row in rows]
    table=Table(data,colWidths=[170*mm/len(headers)]*len(headers),repeatRows=1)
    table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#dfeee8')),('VALIGN',(0,0),(-1,-1),'TOP'),('BOTTOMPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),6),('LINEBELOW',(0,0),(-1,-1),.3,colors.HexColor('#dfeee8'))]))
    SimpleDocTemplate(out,pagesize=(210*mm,297*mm),leftMargin=20*mm,rightMargin=20*mm,title='AeroFlow DEMO').build([paragraph(title),Spacer(1,5*mm),paragraph('DEMO — giao dịch mô phỏng, không phải hóa đơn tài chính'),Spacer(1,5*mm),table])
    out.seek(0);return out
