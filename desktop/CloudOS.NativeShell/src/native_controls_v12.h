#pragma once
#include "native_theme.h"
#include <string>

namespace CloudOS::ControlsV12
{
// Keep the real common control, its accessibility provider, hit testing and
// keyboard behavior. Only its client painting changes.
inline LRESULT CALLBACK PaintSubclass(HWND window,UINT message,WPARAM wp,LPARAM lp,UINT_PTR id,DWORD_PTR slider)
{
    if(message==WM_NCDESTROY) {RemoveWindowSubclass(window,PaintSubclass,id);return DefSubclassProc(window,message,wp,lp);}
    if(message==WM_ERASEBKGND) return 1;
    if(message==WM_PAINT)
    {
        PAINTSTRUCT paint{};HDC dc=BeginPaint(window,&paint);RECT client{};GetClientRect(window,&client);
        HBRUSH background=CreateSolidBrush(WebSkin::BgPrimary);FillRect(dc,&client,background);DeleteObject(background);
        const UINT dpi=GetDpiForWindow(window);const bool enabled=IsWindowEnabled(window)!=FALSE;
        {
            Gdiplus::Graphics g(dc);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
            if(slider)
            {
                RECT track{},thumb{};SendMessageW(window,TBM_GETCHANNELRECT,0,reinterpret_cast<LPARAM>(&track));SendMessageW(window,TBM_GETTHUMBRECT,0,reinterpret_cast<LPARAM>(&thumb));
                const float center=static_cast<float>((thumb.left+thumb.right)/2), y=static_cast<float>(client.bottom/2);
                const float left=static_cast<float>(track.left),right=static_cast<float>(track.right);
                Gdiplus::Pen rail(WebSkin::GdiColor(WebSkin::BgActive),static_cast<float>(Scale(4,dpi)));
                rail.SetStartCap(Gdiplus::LineCapRound);rail.SetEndCap(Gdiplus::LineCapRound);g.DrawLine(&rail,left,y,right,y);
                if(enabled)
                {
                    Gdiplus::Pen fill(WebSkin::GdiColor(WebSkin::Accent),static_cast<float>(Scale(4,dpi)));fill.SetStartCap(Gdiplus::LineCapRound);fill.SetEndCap(Gdiplus::LineCapRound);g.DrawLine(&fill,left,y,std::clamp(center,left,right),y);
                    const float radius=static_cast<float>(Scale(7,dpi));Gdiplus::SolidBrush knob(WebSkin::GdiColor(WebSkin::TextPrimary));g.FillEllipse(&knob,center-radius,y-radius,radius*2,radius*2);
                    if(GetFocus()==window){Gdiplus::Pen focus(WebSkin::GdiColor(WebSkin::Accent),1);g.DrawEllipse(&focus,center-radius-3,y-radius-3,radius*2+6,radius*2+6);}
                }
            }
            else
            {
                WebSkin::DrawRoundedPanel(g,Gdiplus::RectF(1,1,static_cast<float>(client.right-2),static_cast<float>(client.bottom-2)),static_cast<float>(Scale(8,dpi)),WebSkin::GdiColor(WebSkin::BgTertiary),WebSkin::GdiColor(GetFocus()==window?WebSkin::Accent:WebSkin::BorderDefault));
                Gdiplus::Pen arrow(WebSkin::GdiColor(enabled?WebSkin::TextSecondary:WebSkin::TextDisabled),1.5f);
                const float x=static_cast<float>(client.right-Scale(16,dpi)),y=static_cast<float>(client.bottom/2);g.DrawLine(&arrow,x-4,y-2,x,y+2);g.DrawLine(&arrow,x,y+2,x+4,y-2);
            }
        }
        if(!slider)
        {
            const LRESULT selected=SendMessageW(window,CB_GETCURSEL,0,0);std::wstring text;
            if(selected!=CB_ERR){const auto length=SendMessageW(window,CB_GETLBTEXTLEN,selected,0);if(length>0 && length<4096){text.resize(static_cast<std::size_t>(length)+1);SendMessageW(window,CB_GETLBTEXT,selected,reinterpret_cast<LPARAM>(text.data()));text.resize(static_cast<std::size_t>(length));}}
            if(text.empty()) text=L"Nenhum dispositivo disponivel";
            const auto font=reinterpret_cast<HFONT>(SendMessageW(window,WM_GETFONT,0,0));const auto old=SelectObject(dc,font);SetBkMode(dc,TRANSPARENT);SetTextColor(dc,enabled?WebSkin::TextPrimary:WebSkin::TextDisabled);
            client.left+=Scale(10,dpi);client.right-=Scale(32,dpi);DrawTextW(dc,text.c_str(),-1,&client,DT_SINGLELINE|DT_VCENTER|DT_END_ELLIPSIS|DT_NOPREFIX);SelectObject(dc,old);
        }
        EndPaint(window,&paint);return 0;
    }
    const auto result=DefSubclassProc(window,message,wp,lp);
    if(message==WM_SETFOCUS || message==WM_KILLFOCUS || message==WM_ENABLE || message==CB_SETCURSEL || message==CB_RESETCONTENT || message==TBM_SETPOS) InvalidateRect(window,nullptr,FALSE);
    return result;
}
inline void Prepare(HWND control,bool slider){SetWindowSubclass(control,PaintSubclass,0xC512C,slider?1:0);}
}
