import SwiftUI
import AVKit
import AppKit
import PDFKit
import Combine

struct ArtifactCard:View {
    @ObservedObject var store:PromethStore
    let artifact:PromethArtifact
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            Button{store.artifactEditorOpen=false;store.previewArtifact=artifact}label:{
                Color.clear.aspectRatio(16.0/9.0,contentMode:.fit).frame(maxWidth:.infinity)
                    .overlay {Image(nsImage:store.artifactImage(artifact)).resizable().scaledToFill()}
                    .clipped()
                    .overlay {if artifact.kind == "video" {Image(systemName:"play.fill").font(.system(size:18,weight:.semibold)).foregroundStyle(.white).frame(width:46,height:46).background(.black.opacity(0.45),in:Circle())}}
            }.buttonStyle(.plain).accessibilityLabel("Preview \(artifact.kind)")
            HStack(spacing:15) {
                VStack(alignment:.leading,spacing:5) {
                    Text(artifact.kind == "video" ? "Video":"Image").font(.system(size:13,weight:.medium))
                    Text("Version \(artifact.version)"+(artifact.kind == "video" ? " · \(String(format:"%.1f",artifact.duration ?? artifact.trimEnd)) seconds":"")).font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save"){store.saveArtifact(artifact)}
                Button("Edit"){store.artifactEditorOpen=true;store.previewArtifact=artifact}
            }.buttonStyle(.borderless).font(.system(size:12)).padding(17)
        }
        .frame(maxWidth:560)
        .background(Color(nsColor:.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius:16,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:16,style:.continuous).stroke(.primary.opacity(0.10)))
    }
}
@MainActor final class ClipPlayer: ObservableObject {
    let player:AVPlayer; @Published var time:Double=0;@Published var playing=false;@Published var muted=false
    private var observer:Any?
    init(url:URL){player=AVPlayer(url:url);observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.1,preferredTimescale:600),queue:.main){[weak self] value in Task{@MainActor in self?.time=value.seconds;if let duration=self?.player.currentItem?.duration.seconds,duration.isFinite,value.seconds>=duration-0.02{self?.playing=false}}}}
    func toggle(){if playing{player.pause()}else{if let duration=player.currentItem?.duration.seconds,duration.isFinite,time>=duration-0.05{seek(0)};player.play()};playing.toggle()}
    func seek(_ seconds:Double){time=seconds;player.seek(to:CMTime(seconds:seconds,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)}
    func stop(){player.pause();playing=false}
    func cleanup(){stop();if let observer{player.removeTimeObserver(observer);self.observer=nil}}
}
struct PromethArtifactPreview:View {
    @ObservedObject var store:PromethStore;let artifact:PromethArtifact
    @StateObject var player:ClipPlayer;@State var editing=false;@State var prompt="";@State var start:Double=0;@State var end:Double=6;@State var clipDuration:Double=6
    init(store:PromethStore,artifact:PromethArtifact){self.store=store;self.artifact=artifact;_player=StateObject(wrappedValue:ClipPlayer(url:store.artifactURL(artifact)));_editing=State(initialValue:store.artifactEditorOpen);_start=State(initialValue:artifact.trimStart);_end=State(initialValue:artifact.duration ?? artifact.trimEnd);_clipDuration=State(initialValue:artifact.duration ?? artifact.trimEnd)}
    var body:some View {VStack(alignment:.leading,spacing:18){HStack{VStack(alignment:.leading,spacing:4){Text(artifact.kind=="video" ? "Video preview":"Image preview").font(.system(size:20,weight:.medium,design:.rounded));Text("Version \(artifact.version) · \(artifact.parentID == nil ? "Original":"Edited version")").font(.caption).foregroundStyle(.secondary)};Spacer();Button("Save"){store.saveArtifact(artifact)};IconButton(symbol:"xmark",title:"Close preview"){store.previewArtifact=nil}}
            if artifact.kind=="video"{NativeVideoPlayer(player:player.player).aspectRatio(16.0/9.0,contentMode:.fit).frame(maxWidth:.infinity).clipShape(RoundedRectangle(cornerRadius:12,style:.continuous));videoControls}else{Image(nsImage:store.artifactImage(artifact)).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:520).accessibilityLabel("Generated image")}
            Text(artifact.prompt).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)
            if editing {VStack(alignment:.leading,spacing:12){Text(artifact.kind=="video" ? "Trim your clip":"Describe your edit").font(.headline);if artifact.kind=="video" {Text("Adjust In and Out to save a new version.").font(.caption).foregroundStyle(.secondary)}else{TextField("Describe a change to your image…",text:$prompt,axis:.vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)};HStack{Button("Back"){editing=false};Spacer();Button("Create new version"){let text=prompt.trimmingCharacters(in:.whitespacesAndNewlines);store.editArtifact(artifact,prompt:text.isEmpty ? "Trim the clip to \(start.formatted(.number.precision(.fractionLength(1))))–\(end.formatted(.number.precision(.fractionLength(1)))) seconds":text,trim:artifact.kind=="video" ? (start,end):nil)}.buttonStyle(PrimaryButton()).disabled(prompt.isEmpty && artifact.kind != "video")}}}else{HStack{Label("Original saved.",systemImage:"square.stack").font(.caption).foregroundStyle(.secondary);Spacer();Button("\(artifact.kind=="video" ? "Edit video":"Edit image")"){editing=true;player.stop()}.buttonStyle(PrimaryButton())}}
        }.padding(28).frame(width:740).onDisappear{player.cleanup()}.onExitCommand{store.previewArtifact=nil}.task {if artifact.kind=="video",let measured=try? await store.measuredVideoArtifact(artifact){clipDuration=measured.duration ?? clipDuration;start=0;end=clipDuration}}
    }
    var videoControls:some View {VStack(spacing:12){HStack{IconButton(symbol:player.playing ? "pause.fill":"play.fill",title:player.playing ? "Pause video":"Play video"){player.toggle()};Text("\(player.time,specifier:"%.1f") / \(String(format:"%.1f",clipDuration))s").font(.system(size:11,design:.monospaced));Slider(value:Binding(get:{player.time},set:{player.seek($0)}),in:0...max(0.2,clipDuration)).accessibilityLabel("Video playhead");IconButton(symbol:player.muted ? "speaker.slash":"speaker.wave.2",title:"Mute video"){player.muted.toggle();player.player.isMuted=player.muted}}
        if editing{VStack(alignment:.leading,spacing:7){HStack{Label("Trim draft",systemImage:"crop").font(.caption.weight(.semibold));Spacer();Text("\(start,specifier:"%.1f")s – \(end,specifier:"%.1f")s").font(.caption.monospacedDigit())};HStack{Text("In").frame(width:30);Slider(value:Binding(get:{start},set:{start=min($0,end-0.2);player.seek(start)}),in:0...max(0.1,(clipDuration)-0.2)).tint(.coral).accessibilityLabel("Trim start")};HStack{Text("Out").frame(width:30);Slider(value:Binding(get:{end},set:{end=max($0,start+0.2);player.seek(end)}),in:0.2...max(0.2,clipDuration)).tint(.lavender).accessibilityLabel("Trim end")}}.padding(12).background(Color.lavender.opacity(0.1),in:RoundedRectangle(cornerRadius:12))}}}
}
struct AttachmentPreview:View {
    @ObservedObject var store:PromethStore;let attachment:Attachment
    var body:some View {VStack(spacing:18){HStack{Text(attachment.filename).font(.headline);Spacer();IconButton(symbol:"xmark",title:"Close attachment"){store.previewAttachment=nil}};let url=store.attachmentURL(attachment);if let image=NSImage(contentsOf:url){Image(nsImage:image).resizable().scaledToFit().frame(maxHeight:450)}else if url.pathExtension.lowercased()=="pdf"{PDFPreview(url:url).frame(height:440)}else if ["mp4","mov","wav","mp3","m4a"].contains(url.pathExtension.lowercased()){LocalPlayerView(url:url).frame(height:350)}else if let text=try? String(contentsOf:url,encoding:.utf8){ScrollView{Text(text).font(.system(size:13,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(height:350)}else{ContentUnavailableView("Preview unavailable",systemImage:"doc.questionmark",description:Text("The file remains attached to your message."))}}.padding(25).frame(width:680).onExitCommand{store.previewAttachment=nil}}
}
struct PDFPreview:NSViewRepresentable {let url:URL;func makeNSView(context:Context)->PDFView{let v=PDFView();v.autoScales=true;v.document=PDFDocument(url:url);return v};func updateNSView(_ v:PDFView,context:Context){}}
struct LocalPlayerView:View {let url:URL;@State var player=AVPlayer();var body:some View{NativeVideoPlayer(player:player).onAppear{player.replaceCurrentItem(with:AVPlayerItem(url:url))}.onDisappear{player.pause()}}}
struct NativeVideoPlayer:NSViewRepresentable {let player:AVPlayer;func makeNSView(context:Context)->AVPlayerView{let v=AVPlayerView();v.player=player;v.controlsStyle = .none;v.videoGravity = .resizeAspect;v.showsFullScreenToggleButton=false;return v};func updateNSView(_ v:AVPlayerView,context:Context){if v.player !== player{v.player=player};v.videoGravity = .resizeAspect};static func dismantleNSView(_ v:AVPlayerView,coordinator:()){v.player?.pause();v.player=nil}}
