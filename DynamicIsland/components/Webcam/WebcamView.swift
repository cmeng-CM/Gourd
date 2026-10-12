/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AVFoundation
import Defaults
import SwiftUI

struct CameraPreviewView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var webcamManager: WebcamManager
    
    // Track if authorization request is in progress to avoid multiple requests
    @State private var isRequestingAuthorization: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewLayer = webcamManager.previewLayer {
                    CameraPreviewLayerView(previewLayer: previewLayer)
                        .scaleEffect(x: -1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? !Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.closed : MusicPlayerImageSizes.cornerRadiusInset.opened : 100))
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .opacity(webcamManager.isSessionRunning ? 1 : 0)
                }

                if !webcamManager.isSessionRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: Defaults[.mirrorShape] == .rectangle ? !Defaults[.cornerRadiusScaling] ? MusicPlayerImageSizes.cornerRadiusInset.closed : 12 : 100)
                            .fill(Color(red: 20/255, green: 20/255, blue: 20/255))
                            .strokeBorder(.white.opacity(0.04), lineWidth: 1)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                        VStack(spacing: 8) {
                            Image(systemName: webcamManager.authorizationStatus == .denied ? "exclamationmark.triangle" : "web.camera")
                                .foregroundStyle(.gray)
                                .font(.system(size: geometry.size.width/3.5))
                            Text(webcamManager.authorizationStatus == .denied ? "Access Denied" : "Mirror")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .onTapGesture {
                handleCameraTap()
            }
            .onDisappear {
                webcamManager.stopSession()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func handleCameraTap() {
        if isRequestingAuthorization {
            return // Prevent multiple authorization requests
        }
        
        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings to use the mirror feature."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(settingsURL)
                    }
                }
                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }
        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            // Reset the request flag after a reasonable delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isRequestingAuthorization = false
            }
        @unknown default:
            break
        }
    }
}

struct CameraPreviewLayerView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = nsView.bounds
        CATransaction.commit()
    }
}

#Preview {
    CameraPreviewView(webcamManager: WebcamManager.shared)
}

// MARK: - 镜子的浮动预览（p13 / docs/38-home-v5-layout.md D-08）

/// 顶栏镜子按钮弹出的**浮动镜子**：一块固定边长的 `CameraPreviewView`（自带「点一下开 / 关采集」，
/// 消失时停会话），外面套一层深色圆角底 + 柔影——它浮在**面板内容之上**（由 `ContentView` 挂在
/// 面板内容根上、落在 `clipShape` 之内），因此不会出到面板圆角外面。
///
/// **为什么不是 popover**（p13 上屏实测）：popover 在**非激活面板**里撑不住——实测浮层出现后
/// ~0.3s 就被系统收掉（同一块面板里另外三枚 popover 也是这个处境，只是它们的入口在用户的档位下
/// 不可达）。面板内浮层没有这条不确定性：它就在面板自己的窗口里，显隐只由 `vm.isCameraExpanded` 决定。
///
/// **边长 212**（= 预览 200 + 两侧 6pt 内边距）：够看清自己的姿势（这是镜子的用途），
/// 又不会盖住大半块面板。不跟 `mirrorShape` 走：那个键管的是首页块的形状（圆 / 方），
/// 本层是浮层的容器，圆角固定取系统浮层那一档。
struct MirrorFloatingPreview: View {
    @ObservedObject var webcamManager = WebcamManager.shared

    /// 镜面（预览）边长（唯一取值处）。
    static let side: CGFloat = 200
    /// 深色底与预览之间的一圈内边距。
    static let padding: CGFloat = 6
    /// 浮层总边长 = 预览 + 两侧内边距。
    static var totalSide: CGFloat { side + padding * 2 }

    /// 浮层的**上内缩**：让开顶栏那排图标、再留一条可见的缝。
    ///
    /// 浮层挂在面板内容之上、落在 `clipShape` 之内且 `allowsHitTesting(true)`，SwiftUI 的命中测试
    /// 从上层往下走——只要浮层的上沿压在顶栏那排图标（`headerPadding + iconSide` = 8 + 30 = **38**）上，
    /// 鼠标点在镜子按钮的位置就会**先命中浮层**，按钮收不到这次点击，于是「开着镜子再点同一枚按钮
    /// 收起」就点不动了（p17 的用户复现）。因此本值**必须 ≥ 顶栏那排图标的下沿**
    /// （`headerPadding + iconSide`），再多留 `gap` 的缝才是 46——**小于下沿就等于把按钮吞掉**。
    ///
    /// 派生自顶栏自身的几何（而不是在 `ContentView` 里另写一个数）是为了让两者不再各写各的：
    /// 顶栏内边距或按钮边长一改，本函数跟着走，且「不压按钮」这条能被单测直接钉住。
    static func topInset(headerPadding: CGFloat = 8, iconSide: CGFloat = 30, gap: CGFloat = 8) -> CGFloat {
        headerPadding + iconSide + gap
    }

    var body: some View {
        CameraPreviewView(webcamManager: webcamManager)
            .frame(width: Self.side, height: Self.side)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(Self.padding)
            // 最外层钉死尺寸：浮层按内容尺寸排版，而 `CameraPreviewView` 的根是 `GeometryReader`
            // （理想尺寸 10×10）——只在里面钉 `.frame` 会得到一个 ~80pt 的小方块（p13 实测的一版）。
            .frame(width: Self.totalSide, height: Self.totalSide)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(LocalizedStringKey("module.mirror.name")))
    }
}
