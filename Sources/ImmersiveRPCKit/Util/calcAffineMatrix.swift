//
//  CalculateTransformationMatrix.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Accelerate
import simd

func matmul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    let rowsA = A.count
    let colsA = A[0].count
    let colsB = B[0].count

    var result = Array(repeating: Array(repeating: 0.0, count: colsB), count: rowsA)
    for i in 0..<rowsA {
        for j in 0..<colsB {
            for k in 0..<colsA {
                result[i][j] += A[i][k] * B[k][j]
            }
        }
    }
    return result
}

func matrixMul4x4(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
    var result = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    for i in 0..<4 {
        for j in 0..<4 {
            for k in 0..<4 {
                result[i][j] += A[i][k] * B[k][j]
            }
        }
    }
    return result
}

func LU(_ A: [[Double]]) -> ([[Double]], [[Double]]) {
    var L = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    var U = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)

    for i in 0..<4 {
        L[i][i] = 1  // 対角成分は1

        for j in i..<4 {
            var sum: Double = 0.0
            for k in 0..<i {
                sum += L[i][k] * U[k][j]
            }
            U[i][j] = A[i][j] - sum
        }

        for j in (i + 1)..<4 {
            var sum: Double = 0.0
            for k in 0..<i {
                sum += L[j][k] * U[k][i]
            }
            L[j][i] = (A[j][i] - sum) / (U[i][i])
        }
    }

    return (L, U)
}

func eqSolve(_ A: [[Double]], _ Q: [[Double]]) -> [[Double]] {
    var (L, U) = LU(A)
    var Y = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
    var X = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)

    // 前進代入 L * Y = Q
    for i in 0..<4 {
        var dot = [Double](repeating: 0, count: 4)
        for j in 0..<i {
            for k in 0..<4 {
                dot[k] += L[i][j] * Y[j][k]
            }
        }

        for k in 0..<4 {
            Y[i][k] = Q[i][k] - dot[k]
        }
    }

    // 後退代入 U * X = Y
    for i in stride(from: 3, through: 0, by: -1) {
        if abs(U[i][i]) < 1e-8 {  // 0除算防止
            print("Warning: U[\(i), \(i)] is nearly zero. Adding small value.")
            U[i][i] = 1e-8
        }
        var dot: [Double] = [0, 0, 0, 0]
        for j in stride(from: 3, through: i + 1, by: -1) {
            for k in 0..<4 {
                dot[k] += U[i][j] * X[j][k]
            }
        }
        for k in 0..<4 {
            X[i][k] = (Y[i][k] - dot[k]) / U[i][i]
        }
    }

    return X
}

func svd(_ matrix: simd_double3x3) -> (U: simd_double3x3, S: simd_double3, V: simd_double3x3) {
    var a: [Double] = [
        matrix[0][0], matrix[0][1], matrix[0][2],
        matrix[1][0], matrix[1][1], matrix[1][2],
        matrix[2][0], matrix[2][1], matrix[2][2],
    ]
    var s = [Double](repeating: 0, count: 3)
    var u = [Double](repeating: 0, count: 9)
    var vt = [Double](repeating: 0, count: 9)
    var info = Int32(0)
    var lwork = Int32(-1)
    var work = [Double](repeating: 0, count: 1)

    var m = Int32(3)
    var n = Int32(3)
    var lda = m
    var ldu = m
    var ldvt = n
    var jobu: Int8 = 65  // 'A'
    var jobvt: Int8 = 65  // 'A'

    // Query and allocate the optimal workspace
    dgesvd_(&jobu, &jobvt, &m, &n, &a, &lda, &s, &u, &ldu, &vt, &ldvt, &work, &lwork, &info)

    lwork = Int32(work[0])
    work = [Double](repeating: 0, count: Int(lwork))

    // Compute SVD
    dgesvd_(&jobu, &jobvt, &m, &n, &a, &lda, &s, &u, &ldu, &vt, &ldvt, &work, &lwork, &info)

    var U = simd_double3x3()
    var V = simd_double3x3()
    var S = simd_double3()

    for i in 0..<3 {
        S[i] = s[i]
        for j in 0..<3 {
            U[j][i] = u[i * 3 + j]
            V[i][j] = vt[j * 3 + i]
        }
    }

    return (U, S, V)
}

func dotsimd_double3x3(_ a: simd_double3x3, _ b: simd_double3x3) -> simd_double3x3 {
    var result = simd_double3x3()
    for i in 0..<3 {
        for j in 0..<3 {
            result[i][j] = a[i].x * b[0][j] + a[i].y * b[1][j] + a[i].z * b[2][j]
        }
    }
    return result
}

func polar(_ M: simd_double3x3) -> (simd_double3x3, simd_double3x3) {
    let (w, _, vh) = svd(M)
    // 内積を計算
    let u = simd_mul(vh, w)
    let p: simd_double3x3 = .init()
    return (u, p)
}

func removeScaleAffineMatrix(_ matrix: [[Double]]) -> [[Double]] {
    // 3x3 部分行列 (回転 + スケーリング)
    let M = simd_double3x3(
        SIMD3<Double>(matrix[0][0], matrix[1][0], matrix[2][0]),
        SIMD3<Double>(matrix[0][1], matrix[1][1], matrix[2][1]),
        SIMD3<Double>(matrix[0][2], matrix[1][2], matrix[2][2])
    )

    // 特異値分解
    let (R, _) = polar(M)

    var newMatrix = matrix

    for i in 0..<3 {
        for j in 0..<3 {
            newMatrix[i][j] = Double(R[i][j])
        }
    }

    return newMatrix
}

func matmul4x4_4x1(_ A: [[Double]], _ B: [Double]) -> [Double] {
    var result = [Double](repeating: 0, count: 4)
    for i in 0..<4 {
        for j in 0..<3 {
            result[i] += A[i][j] * B[j]
        }
        result[i] += A[i][3]
    }
    return result
}

func matmul4x4_4x1(_ A: [[Float]], _ B: [Float]) -> [Float] {
    var result = [Float](repeating: 0, count: 4)
    for i in 0..<4 {
        for j in 0..<3 {
            result[i] += A[i][j] * B[j]
        }
        result[i] += A[i][3]
    }
    return result
}

func matmul4x4_4x1(_ A: simd_float4x4, _ B: SIMD4<Float>) -> SIMD3<Float> {
    let Am: [[Float]] = A.floatList
    let Bm: [Float] = [B.x, B.y, B.z, 1.0]
    let result = matmul4x4_4x1(Am, Bm)
    return SIMD3<Float>(result[0], result[1], result[2])
}

func matmul4x4_3x1(_ A: simd_float4x4, _ B: SIMD3<Float>) -> SIMD3<Float> {
    let Am: [[Float]] = A.floatList
    let Bm: [Float] = [B.x, B.y, B.z, 1.0]
    let result = matmul4x4_4x1(Am, Bm)
    return SIMD3<Float>(result[0], result[1], result[2])
}

func affineMatrixToAngle(_ matrix: [[Double]]) -> (Double, Double, Double) {
    let x = atan2(matrix[2][1], matrix[2][2])
    let y = atan2(-matrix[2][0], sqrt(pow(matrix[2][1], 2) + pow(matrix[2][2], 2)))
    let z = atan2(matrix[1][0], matrix[0][0])
    return (x, y, z)
}

func calcRotation(_ A: [[[Double]]], _ B: [[[Double]]], _ affineMatrix: [[Double]]) -> [[Double]] {
    // A[1],A[2],A[3] の位置 から A[0]の位置を引いた情報を集める
    // let shiftA0: [Double] = [
    //     A[0][0][3] - A[0][0][3],
    //     A[0][1][3] - A[0][1][3],
    //     A[0][2][3] - A[0][2][3]
    // ]
    // let shiftA1: [Double] = [
    //     A[1][0][3] - A[0][0][3],
    //     A[1][1][3] - A[0][1][3],
    //     A[1][2][3] - A[0][2][3]
    // ]
    let shiftA2: [Double] = [
        A[2][0][3] - A[0][0][3],
        A[2][1][3] - A[0][1][3],
        A[2][2][3] - A[0][2][3],
    ]
    let shiftA3: [Double] = [
        A[3][0][3] - A[0][0][3],
        A[3][1][3] - A[0][1][3],
        A[3][2][3] - A[0][2][3],
    ]

    // let shiftB0: [Double] = [
    //     B[0][0][3] - B[0][0][3],
    //     B[0][1][3] - B[0][1][3],
    //     B[0][2][3] - B[0][2][3]
    // ]
    // let shiftB1: [Double] = [
    //     B[1][0][3] - B[0][0][3],
    //     B[1][1][3] - B[0][1][3],
    //     B[1][2][3] - B[0][2][3]
    // ]
    let shiftB2: [Double] = [
        B[2][0][3] - B[0][0][3],
        B[2][1][3] - B[0][1][3],
        B[2][2][3] - B[0][2][3],
    ]
    // let shiftB3: [Double] = [
    //     B[3][0][3] - B[0][0][3],
    //     B[3][1][3] - B[0][1][3],
    //     B[3][2][3] - B[0][2][3]
    // ]

    // y軸の補正にx軸の三角比を利用する
    let ySin = shiftB2[2] * -1
    let yCos = shiftB2[0] * -1

    print("ySin: \(ySin), yCos: \(yCos)")
    let yasin = asin(ySin)
    let yasindegree = yasin * 180 / .pi
    print("yasin: \(yasin), yasindegree: \(yasindegree)")

    // x軸の補正
    let xSin: Double = shiftA2[1] / shiftA2[0]
    var xCos: Double
    // A 側の y軸が x軸基準の方が高い場合は cosはプラスになる
    if A[0][1][3] < A[2][1][3] {
        xCos = sqrt(1 - pow(xSin, 2))
    } else {
        xCos = -sqrt(1 - pow(xSin, 2))
    }

    print("xSin: \(xSin), xCos: \(xCos)")
    let xasin = asin(xSin)
    let xasindegree = xasin * 180 / .pi
    print("xasin: \(xasin), xasindegree: \(xasindegree)")

    let zSin: Double = shiftA3[1] / shiftA3[2]
    var zCos: Double
    // A 側の x軸が z軸基準の方が高い場合は cosはプラスになる
    if A[0][0][3] < A[3][0][3] {
        zCos = sqrt(1 - pow(zSin, 2))
    } else {
        zCos = -sqrt(1 - pow(zSin, 2))
    }

    print("zSin: \(zSin), zCos: \(zCos)")
    let zasin = asin(zSin)
    let zasindegree = zasin * 180 / .pi
    print("zasin: \(zasin), zasindegree: \(zasindegree)")

    // 回転行列を計算
    let rotationMatrixX: [[Double]] = [
        [1, 0, 0, 0],
        [0, xCos, xSin, 0],
        [0, -xSin, xCos, 0],
        [0, 0, 0, 1],
    ]
    let rotationMatrixY: [[Double]] = [
        [yCos, 0, -ySin, 0],
        [0, 1, 0, 0],
        [ySin, 0, yCos, 0],
        [0, 0, 0, 1],
    ]
    let rotationMatrixZ: [[Double]] = [
        [zCos, zSin, 0, 0],
        [-zSin, zCos, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1],
    ]

    // 回転行列を合成
    let rotationMatrix = matrixMul4x4(
        matrixMul4x4(matrixMul4x4(rotationMatrixX, rotationMatrixY), rotationMatrixZ), affineMatrix)

    return rotationMatrix
}

func shiftRotateAffineMatrix(_ A: [[[Double]]], _ B: [[[Double]]], _ affineMatrix: [[Double]])
    -> [[Double]]
{
    let tmpAffineMatrix: [[Double]] = calcRotation(A, B, affineMatrix)
    return tmpAffineMatrix
}

/*
 let A:[[[Double]]] = [
 [[1, 0, 0, 7],[0, 1, 0, 9],[0, 0, 1, 8],[0, 0, 0, 1]],
 [[1, 0, 0, 7],[0, 1, 0, 7],[0, 0, 1, 8],[0, 0, 0, 1]],
 [[1, 0, 0, 23],[0, 1, 0, 25],[0, 0, 1, 23],[0, 0, 0, 1]],
 ]

 let B:[[[Double]]] = [
 [[1, 0, 0, 13],[0, 1, 0, 15],[0, 0, 1, 14],[0, 0, 0, 1]],
 [[1, 0, 0, 15],[0, 1, 0, 15],[0, 0, 1, 16],[0, 0, 0, 1]],
 [[1, 0, 0, 33],[0, 1, 0, 35],[0, 0, 1, 33],[0, 0, 0, 1]],
 ]

 calcAffineMatrix(A, B)
 */
func calcAffineMatrix(_ A: [[[Double]]], _ B: [[[Double]]]) -> [[Double]] {
    let n = A.count

    var P: [[Double]] = []
    for i in (0..<n) {
        var rowP: [Double] = []
        for j in (0..<3) {
            rowP.append(A[i][j][3])
        }
        rowP.append(1.0)
        P.append(rowP)
    }
    if P.count == 3 {
        P.append([0, 0, 0, 0])
    }

    var Q: [[Double]] = []
    for i in (0..<n) {
        var rowQ: [Double] = []
        for j in (0..<3) {
            rowQ.append(B[i][j][3])
        }
        rowQ.append(0.0)
        Q.append(rowQ)
    }
    if Q.count == 3 {
        Q.append([0, 0, 0, 0])
    }

    let eqSolveMatrix: [[Double]] = matrixMul4x4(
        eqSolve(matrixMul4x4(P.transpose4x4, P), P.transpose4x4), Q)
    var affineMatrix: [[Double]] = eqSolveMatrix.transpose4x4
    affineMatrix[3][3] = 1.0
    print("default")
    print(affineMatrix)

    affineMatrix = removeScaleAffineMatrix(affineMatrix)
    print("removeScaleAffineMatrix")
    print(affineMatrix)

    //    let rotateAffineMatrix = shiftRotateAffineMatrix(A, B, affineMatrix)
    //    print("shiftRotateAffineMatrix")
    //    print(rotateAffineMatrix)
    //    if !rotateAffineMatrix.isIncludeNaN {
    //        affineMatrix = rotateAffineMatrix
    //    }

    return affineMatrix
}

// 逆行列を計算する関数
func inverseMatrix(_ matrix: [[Double]]) -> [[Double]] {
    let n = matrix.count
    guard n == 4 else {
        fatalError("Only 4x4 matrices are supported.")
    }

    var augmentedMatrix = matrix
    var identityMatrix = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)

    // 単位行列を作成
    for i in 0..<n {
        identityMatrix[i][i] = 1.0
    }

    // 拡大行列を作成
    for i in 0..<n {
        augmentedMatrix[i].append(contentsOf: identityMatrix[i])
    }

    // ガウス・ジョルダン法で逆行列を計算
    for i in 0..<n {
        // 対角成分を1にする
        let diagElement = augmentedMatrix[i][i]
        if abs(diagElement) < 1e-8 {
            fatalError("Matrix is singular and cannot be inverted.")
        }
        for j in 0..<(2 * n) {
            augmentedMatrix[i][j] /= diagElement
        }

        // 他の行を0にする
        for k in 0..<n {
            if k != i {
                let factor = augmentedMatrix[k][i]
                for j in 0..<(2 * n) {
                    augmentedMatrix[k][j] -= factor * augmentedMatrix[i][j]
                }
            }
        }
    }

    // 逆行列を抽出
    var inverseMatrix = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
    for i in 0..<n {
        inverseMatrix[i] = Array(augmentedMatrix[i][n..<(2 * n)])
    }

    return inverseMatrix
}
