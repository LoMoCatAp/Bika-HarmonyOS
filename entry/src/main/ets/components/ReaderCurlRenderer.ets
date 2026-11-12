/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and limitations under the License.
 *
 * Based on the bitmap/RenderNode approach in HarmonyOS_Samples/PageFlip.
 * Modified by Bika-HarmonyOS in 2026: image-bounded paper surfaces, two-dimensional
 * drag-controlled folding, original-color textures and continuous native meshes.
 */
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { NodeController, FrameNode, RenderNode, DrawContext, UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { buildReaderPaperMesh, ReaderPaperParameters, ReaderPaperRect } from '../models/ReaderSpineMesh';

export interface ReaderCurlFrame extends ReaderPaperParameters {
  current: image.PixelMap;
  next: image.PixelMap;
  progress: number;
  completed: boolean;
}

class ReaderCurlRenderNode extends RenderNode {
  content: ReaderCurlFrame | null = null;

  draw(context: DrawContext): void {
    const frame = this.content;
    if (frame === null) {
      return;
    }
    const canvas = context.canvas;
    const full: common2D.Rect = { left: 0, top: 0, right: frame.width, bottom: frame.height };
    const brush = new drawing.Brush();
    brush.setAntiAlias(true);
    brush.setColor(0xFFFFFFFF);
    canvas.attachBrush(brush);
    if (frame.completed || (frame.touchX >= frame.frontRect.right - frame.frontRect.left
      && Math.abs(frame.touchY - frame.cornerY) < 0.001)) {
      canvas.drawImageRect(frame.completed ? frame.next : frame.current, full);
      canvas.detachBrush();
      return;
    }
    const mesh = buildReaderPaperMesh(frame);
    if (mesh === null) {
      canvas.drawImageRect(frame.current, full);
      canvas.detachBrush();
      return;
    }
    canvas.save();
    canvas.clipRect(full);
    canvas.drawImageRect(frame.paired ? frame.current : frame.next, full);
    if (frame.paired) {
      canvas.save();
      const spine = (frame.frontRect.left + frame.backRect.right) / 2;
      const otherSpine = (frame.frontRect.right + frame.backRect.left) / 2;
      canvas.clipRect({ left: frame.fromRight ? spine : 0, top: 0,
        right: frame.fromRight ? frame.width : otherSpine, bottom: frame.height });
      canvas.drawImageRect(frame.next, full);
      canvas.restore();
    }
    // 完整快照只作为纹理；留白的 UV 收拢到实际图片边界，不会变成灰色纸板。
    canvas.drawPixelMapMesh(frame.current, mesh.columns, mesh.rows, mesh.front.vertices, 0, mesh.front.colors, 0);
    canvas.drawPixelMapMesh(frame.paired ? frame.next : frame.current, mesh.columns, mesh.rows,
      mesh.back.vertices, 0, mesh.back.colors, 0);
    canvas.detachBrush();
    canvas.restore();
  }
}

export class ReaderCurlNodeController extends NodeController {
  private root: FrameNode | null = null;
  private node: ReaderCurlRenderNode = new ReaderCurlRenderNode();
  private nodeWidth: number = 0;
  private nodeHeight: number = 0;

  makeNode(context: UIContext): FrameNode {
    this.root = new FrameNode(context);
    this.root.getRenderNode()?.appendChild(this.node);
    this.resize(this.nodeWidth, this.nodeHeight);
    return this.root;
  }

  resize(width: number, height: number): void {
    this.nodeWidth = width;
    this.nodeHeight = height;
    const root = this.root?.getRenderNode();
    if (root !== null && root !== undefined) {
      root.frame = { x: 0, y: 0, width, height };
    }
    this.node.frame = { x: 0, y: 0, width, height };
  }

  show(frame: ReaderCurlFrame): void {
    this.node.content = frame;
    this.node.invalidate();
  }

  clear(): void {
    this.node.content = null;
    this.node.invalidate();
  }

  dispose(): void {
    this.clear();
    this.root?.getRenderNode()?.clearChildren();
    this.root?.dispose();
    this.root = null;
    this.node.dispose();
  }
}
