// Sic.ShellExt - Windows 11 モダン コンテキスト メニュー用 IExplorerCommand ハンドラ (PoC)
//
// .lnk を右クリックしたときにモダン メニュー（第一階層）へ「アイコンを変更」を出し、
// クリックで隣の ShortcutIconChanger.exe を選択された .lnk 付きで起動するだけの薄いランチャ。
// WRL/ATL に依存しない生 COM 実装。CRT は静的リンク (/MT) で追加ランタイム依存なし。
//
// 日本語リテラルは codepage 事故を避けるため \u エスケープで記述する。

#include <windows.h>
#include <shobjidl_core.h>
#include <shlwapi.h>
#include <strsafe.h>
#include <new>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")

// {B6E6D7EA-EEBA-4B94-84CE-E34DCF06AD5C}
static const GUID CLSID_ChangeIconCommand =
    { 0xB6E6D7EA, 0xEEBA, 0x4B94, { 0x84, 0xCE, 0xE3, 0x4D, 0xCF, 0x06, 0xAD, 0x5C } };

static HMODULE g_hModule = nullptr;
static LONG    g_cRef     = 0;   // サーバ全体の生存オブジェクト/ロック数

// このDLLと同じフォルダにある ShortcutIconChanger.exe のフルパスを得る。
static bool GetAppExePath(wchar_t* out, size_t cch)
{
    wchar_t dll[MAX_PATH];
    DWORD n = GetModuleFileNameW(g_hModule, dll, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return false;
    wchar_t* slash = wcsrchr(dll, L'\\');
    if (!slash) return false;
    *(slash + 1) = L'\0';
    if (FAILED(StringCchCopyW(out, cch, dll))) return false;
    if (FAILED(StringCchCatW(out, cch, L"ShortcutIconChanger.exe"))) return false;
    return true;
}

static bool IsJapaneseUi()
{
    return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_JAPANESE;
}

// 選択が「単一の .lnk」かどうか。モダン メニューは Type="*" で登録し、ここで
// .lnk 以外を ECS_HIDDEN にすることでショートカットのときだけ項目を出す。
static bool IsSingleLnk(IShellItemArray* items)
{
    if (!items) return false;
    DWORD count = 0;
    if (FAILED(items->GetCount(&count)) || count != 1) return false;

    IShellItem* item = nullptr;
    if (FAILED(items->GetItemAt(0, &item)) || !item) return false;

    bool ok = false;
    PWSTR path = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path)
    {
        PCWSTR ext = PathFindExtensionW(path);
        ok = (ext && _wcsicmp(ext, L".lnk") == 0);
        CoTaskMemFree(path);
    }
    item->Release();
    return ok;
}

class ChangeIconCommand : public IExplorerCommand
{
public:
    ChangeIconCommand() : _ref(1) { InterlockedIncrement(&g_cRef); }

    // IUnknown
    IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv)
    {
        static const QITAB qit[] =
        {
            QITABENT(ChangeIconCommand, IExplorerCommand),
            { nullptr, 0 },
        };
        return QISearch(this, qit, riid, ppv);
    }
    IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&_ref); }
    IFACEMETHODIMP_(ULONG) Release()
    {
        ULONG r = InterlockedDecrement(&_ref);
        if (r == 0) delete this;
        return r;
    }

    // IExplorerCommand
    IFACEMETHODIMP GetTitle(IShellItemArray*, LPWSTR* ppszName)
    {
        // 「アイコンを変更」 / "Change icon"
        return SHStrDupW(IsJapaneseUi() ? L"\u30A2\u30A4\u30B3\u30F3\u3092\u5909\u66F4"
                                        : L"Change icon", ppszName);
    }
    IFACEMETHODIMP GetIcon(IShellItemArray*, LPWSTR* ppszIcon)
    {
        wchar_t exe[MAX_PATH];
        if (!GetAppExePath(exe, ARRAYSIZE(exe))) { *ppszIcon = nullptr; return E_FAIL; }
        wchar_t icon[MAX_PATH + 8];
        if (FAILED(StringCchPrintfW(icon, ARRAYSIZE(icon), L"%s,0", exe))) { *ppszIcon = nullptr; return E_FAIL; }
        return SHStrDupW(icon, ppszIcon);
    }
    IFACEMETHODIMP GetToolTip(IShellItemArray*, LPWSTR* ppszInfotip) { *ppszInfotip = nullptr; return E_NOTIMPL; }
    IFACEMETHODIMP GetCanonicalName(GUID* pguid) { *pguid = GUID_NULL; return S_OK; }
    IFACEMETHODIMP GetState(IShellItemArray* psiItemArray, BOOL, EXPCMDSTATE* pCmdState)
    {
        // .lnk 単一選択のときだけ表示する。
        *pCmdState = IsSingleLnk(psiItemArray) ? ECS_ENABLED : ECS_HIDDEN;
        return S_OK;
    }
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS* pFlags) { *pFlags = ECF_DEFAULT; return S_OK; }
    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** ppEnum) { *ppEnum = nullptr; return E_NOTIMPL; }

    IFACEMETHODIMP Invoke(IShellItemArray* psiItemArray, IBindCtx*)
    {
        if (!psiItemArray) return E_INVALIDARG;
        DWORD count = 0;
        if (FAILED(psiItemArray->GetCount(&count)) || count == 0) return S_OK;

        IShellItem* item = nullptr;
        HRESULT hr = psiItemArray->GetItemAt(0, &item);
        if (FAILED(hr)) return hr;

        PWSTR path = nullptr;
        hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
        if (SUCCEEDED(hr) && path)
        {
            wchar_t exe[MAX_PATH];
            if (GetAppExePath(exe, ARRAYSIZE(exe)))
            {
                wchar_t args[MAX_PATH + 4];
                if (SUCCEEDED(StringCchPrintfW(args, ARRAYSIZE(args), L"\"%s\"", path)))
                    ShellExecuteW(nullptr, L"open", exe, args, nullptr, SW_SHOWNORMAL);
            }
            CoTaskMemFree(path);
        }
        item->Release();
        return S_OK;
    }

private:
    ~ChangeIconCommand() { InterlockedDecrement(&g_cRef); }
    LONG _ref;
};

class ClassFactory : public IClassFactory
{
public:
    ClassFactory() : _ref(1) { InterlockedIncrement(&g_cRef); }

    IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv)
    {
        static const QITAB qit[] =
        {
            QITABENT(ClassFactory, IClassFactory),
            { nullptr, 0 },
        };
        return QISearch(this, qit, riid, ppv);
    }
    IFACEMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&_ref); }
    IFACEMETHODIMP_(ULONG) Release()
    {
        ULONG r = InterlockedDecrement(&_ref);
        if (r == 0) delete this;
        return r;
    }

    IFACEMETHODIMP CreateInstance(IUnknown* pOuter, REFIID riid, void** ppv)
    {
        *ppv = nullptr;
        if (pOuter) return CLASS_E_NOAGGREGATION;
        ChangeIconCommand* p = new (std::nothrow) ChangeIconCommand();
        if (!p) return E_OUTOFMEMORY;
        HRESULT hr = p->QueryInterface(riid, ppv);
        p->Release();
        return hr;
    }
    IFACEMETHODIMP LockServer(BOOL fLock)
    {
        if (fLock) InterlockedIncrement(&g_cRef); else InterlockedDecrement(&g_cRef);
        return S_OK;
    }

private:
    ~ClassFactory() { InterlockedDecrement(&g_cRef); }
    LONG _ref;
};

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv)
{
    if (!IsEqualCLSID(rclsid, CLSID_ChangeIconCommand)) return CLASS_E_CLASSNOTAVAILABLE;
    ClassFactory* f = new (std::nothrow) ClassFactory();
    if (!f) return E_OUTOFMEMORY;
    HRESULT hr = f->QueryInterface(riid, ppv);
    f->Release();
    return hr;
}

STDAPI DllCanUnloadNow()
{
    return (g_cRef == 0) ? S_OK : S_FALSE;
}

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_hModule = hInst;
        DisableThreadLibraryCalls(hInst);
    }
    return TRUE;
}
